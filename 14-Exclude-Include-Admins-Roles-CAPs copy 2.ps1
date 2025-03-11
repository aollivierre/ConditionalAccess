#Requires -Modules Microsoft.Graph.Identity.DirectoryManagement, Microsoft.Graph.Identity.SignIns, PSWriteHTML


function Get-ConditionalAccessPoliciesDetails {
    [CmdletBinding()]
    param()
    
    try {
        $policies = Get-MgIdentityConditionalAccessPolicy -All
        
        $formattedPolicies = foreach ($policy in $policies) {
            # Extract current version from display name
            $version = if ($policy.DisplayName -match '-v(\d+\.\d+)$') {
                [decimal]$matches[1]
            } else {
                1.0
            }
            
            # Build the admin roles status string
            $adminRolesStatus = [System.Collections.ArrayList]::new()
            
            if ($policy.Conditions.Users.IncludeRoles.Count -gt 0) {
                $null = $adminRolesStatus.Add("Include: $($policy.Conditions.Users.IncludeRoles.Count) roles")
            }
            
            if ($policy.Conditions.Users.ExcludeRoles.Count -gt 0) {
                $null = $adminRolesStatus.Add("Exclude: $($policy.Conditions.Users.ExcludeRoles.Count) roles")
            }
            
            $currentAdminRoles = if ($adminRolesStatus.Count -gt 0) {
                $adminRolesStatus -join ' | '
            } else {
                "No admin roles configured"
            }
            
            [PSCustomObject]@{
                DisplayName = $policy.DisplayName
                Id = $policy.Id
                State = $policy.State
                Version = $version
                CurrentAdminRoles = $currentAdminRoles
            }
        }
        
        return $formattedPolicies
    }
    catch {
        Write-Error "Failed to retrieve Conditional Access Policies: $_"
        return $null
    }
}


function Get-EntraAdminRolesDetailed {
    [CmdletBinding()]
    param()
    
    try {
        Write-Verbose "Retrieving directory role templates..."
        $roleTemplates = Get-MgBetaDirectoryRoleTemplate -All
        
        Write-Host "`nProcessing roles..." -ForegroundColor Cyan
        
        $skippedRoles = [System.Collections.ArrayList]::new()
        $formattedRoles = foreach ($role in $roleTemplates) {
            # Check for roles to skip
            $skipReason = switch -Regex ($true) {
                { $role.DisplayName -match '^Device Managers' } { "Device Manager Role" }
                { $role.DisplayName -match '^Device Users' } { "Device Users Role" }
                { $role.DisplayName -match '^Partner' } { "Partner Role" }
                { $role.DisplayName -match '^Device Join' } { "Device Join Role" }
                { $role.DisplayName -match '^Workplace Device Join' } { "Workplace Device Join Role" }
                { $role.Description -match 'deprecated' } { "Deprecated Role" }
                { $role.Description -match 'do not use' } { "Do Not Use Role" }
                { $role.Description -match 'default role for' } { "Default Role" }
                { $null -eq $role.Id } { "Invalid ID" }
                default { $null }
            }

            if ($skipReason) {
                $null = $skippedRoles.Add([PSCustomObject]@{
                        DisplayName = $role.DisplayName
                        Reason      = $skipReason
                    })
                continue
            }
            
            # Convert GUID to proper format if needed
            $roleId = $role.Id
            if ($roleId -notmatch '^[{]?[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}[}]?$') {
                Write-Verbose "Skipping role with invalid ID format: $($role.DisplayName)"
                continue
            }
            
            [PSCustomObject]@{
                DisplayName = $role.DisplayName
                Id          = $roleId
                Description = $role.Description
                Category    = switch -Regex ($role.DisplayName) {
                    'Global Admin|Administrator' { 'Administrative' }
                    'Reader' { 'Reader' }
                    'Owner' { 'Owner' }
                    'Operator' { 'Operator' }
                    default { 'Other' }
                }
                IsBuiltIn   = $true
                TemplateId  = $role.Id
            }
        }
        
        # Sort roles by category and display name
        $sortedRoles = $formattedRoles | Sort-Object Category, DisplayName
        
        # Display summary of skipped roles
        Write-Host "`nSkipped Roles Summary:" -ForegroundColor Yellow
        Write-Host "=====================" -ForegroundColor Yellow
        
        $groupedSkipped = $skippedRoles | Group-Object Reason
        foreach ($group in $groupedSkipped) {
            Write-Host "`n$($group.Name):" -ForegroundColor Yellow
            foreach ($role in $group.Group) {
                Write-Host "  - $($role.DisplayName)" -ForegroundColor Gray
            }
        }
        
        Write-Host "`nAvailable Roles Count: $($sortedRoles.Count)" -ForegroundColor Green
        Write-Host "Skipped Roles Count: $($skippedRoles.Count)" -ForegroundColor Yellow
        
        return $sortedRoles
    }
    catch {
        Write-Error "Failed to retrieve admin roles: $_"
        return $null
    }
}


function Export-AdminRolesReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Results,
        
        [Parameter(Mandatory)]
        [string]$OutputDir,
        
        [Parameter()]
        [string]$ReportName = "AdminRoles_CAPolicy_Update"
    )
    
    # Create output directory if it doesn't exist
    if (-not (Test-Path -Path $OutputDir)) {
        $null = New-Item -ItemType Directory -Path $OutputDir -Force
    }
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $htmlPath = Join-Path $OutputDir "$($ReportName)_$timestamp.html"
    $csvPath = Join-Path $OutputDir "$($ReportName)_$timestamp.csv"
    
    # Export to CSV
    $Results | Export-Csv -Path $csvPath -NoTypeInformation
    
    New-HTML -TitleText "Admin Roles Policy Update Report" -FilePath $htmlPath -ShowHTML {
        New-HTMLSection -HeaderText "Policy Update Summary" {
            New-HTMLPanel {
                New-HTMLText -Text @"
                <h3>Update Details</h3>
                <ul>
                    <li>Total Policies Updated: $($Results.Count)</li>
                    <li>Operation Performed: $($Results[0].Operation)</li>
                    <li>Generated On: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</li>
                </ul>
"@
            }
        }
        
        New-HTMLSection -HeaderText "Updated Policies" {
            New-HTMLTable -DataTable $Results -ScrollX {
                New-TableCondition -Name 'Status' -ComparisonType string -Operator eq -Value 'Success' -BackgroundColor LightGreen -Color Black
                New-TableCondition -Name 'Status' -ComparisonType string -Operator eq -Value 'Failed' -BackgroundColor Salmon -Color Black
            } -Buttons @('copyHtml5', 'excelHtml5', 'csvHtml5', 'searchBuilder')
        }
    }

    Write-Host "`nReports generated:" -ForegroundColor Green
    Write-Host "CSV Report: $csvPath" -ForegroundColor Green
    Write-Host "HTML Report: $htmlPath" -ForegroundColor Green

    return @{
        CSVPath  = $csvPath
        HTMLPath = $htmlPath
    }
}

function Show-OperationMenu {
    [CmdletBinding()]
    param()
    
    $menuText = @"

====== Conditional Access Policy Role Operation ======

Select an operation:
[I] Include Admin Roles
[E] Exclude Admin Roles
[C] Cancel Operation

Enter your choice [I/E/C]: 
"@
    
    do {
        $choice = Read-Host -Prompt $menuText
        switch ($choice.ToUpper()) {
            'I' { return 'Include' }
            'E' { return 'Exclude' }
            'C' { return 'Cancel' }
            default {
                Write-Host "Invalid selection. Please try again." -ForegroundColor Yellow
            }
        }
    } while ($true)
}

function Update-ConditionalAccessPolicyAdminRoles {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$OutputPath = ".\Reports"
    )
    
    try {
        # Show welcome message
        Write-Host "`nConditional Access Policy Admin Roles Update Tool" -ForegroundColor Cyan
        Write-Host "=================================================" -ForegroundColor Cyan
        
        # Get operation choice from user
        $operation = Show-OperationMenu
        if ($operation -eq 'Cancel') {
            Write-Host "`nOperation cancelled by user." -ForegroundColor Yellow
            return
        }
        
        Write-Host "`nSelected Operation: $operation" -ForegroundColor Green



        # Get fresh policy data before selection
        Write-Host "`nRetrieving current policy information..." -ForegroundColor Cyan
        $policies = Get-ConditionalAccessPoliciesDetails
        if (-not $policies) { 
            Write-Warning "No policies found or error retrieving policies."
            return 
        }
                
        $selectedPolicies = $policies | 
        Out-GridView -Title "Select Conditional Access Policies to Modify" -PassThru
                
        if (-not $selectedPolicies) {
            Write-Warning "No policies selected. Operation cancelled."
            return
        }

        
    
        
        Write-Host "`nRetrieving admin roles..." -ForegroundColor Cyan
        $adminRoles = Get-EntraAdminRolesDetailed
        if (-not $adminRoles) { 
            Write-Warning "No admin roles found or error retrieving roles."
            return 
        }
        
        $selectedRoles = $adminRoles | 
        Out-GridView -Title "Select Admin Roles to $Operation" -PassThru
        
        if (-not $selectedRoles) {
            Write-Warning "No roles selected. Operation cancelled."
            return
        }
        
        # Enhanced operation summary
        Write-Host "`nOperation Summary:" -ForegroundColor Cyan
        Write-Host "==================" -ForegroundColor Cyan
        Write-Host "Operation: $operation admin roles" -ForegroundColor White
        Write-Host "`nSelected Policies:" -ForegroundColor White
        foreach ($policy in $selectedPolicies) {
            Write-Host "- $($policy.DisplayName)" -ForegroundColor Gray
        }
        Write-Host "`nSelected Roles ($($selectedRoles.Count)):" -ForegroundColor White
          
        $confirm = Read-Host "`nDo you want to proceed? [Y/N]"
        if ($confirm -notmatch '^[Yy]$') {
            Write-Host "`nOperation cancelled by user." -ForegroundColor Yellow
            return
        }
        
        $results = [System.Collections.ArrayList]::new()
        
        foreach ($policy in $selectedPolicies) {
            try {
                Write-Verbose "Processing policy: $($policy.DisplayName)"
                $policyDetail = Get-MgBetaIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $policy.Id



                    # Increment version in display name
                    $newVersion = $policy.Version + 0.1
                    $newDisplayName = if ($policy.DisplayName -match '-v\d+\.\d+$') {
                        $policy.DisplayName -replace '-v\d+\.\d+$', "-v$newVersion"
                    }
                    else {
                        "$($policy.DisplayName)-v$newVersion"
                    }
                    
                 
                
                # Build the users condition preserving existing settings
                $usersCondition = @{
                    includeUsers  = @(if ($policyDetail.Conditions.Users.IncludeUsers) { $policyDetail.Conditions.Users.IncludeUsers } else { "None" })
                    excludeUsers  = @(if ($policyDetail.Conditions.Users.ExcludeUsers) { $policyDetail.Conditions.Users.ExcludeUsers } else { })
                    includeGroups = @(if ($policyDetail.Conditions.Users.IncludeGroups) { $policyDetail.Conditions.Users.IncludeGroups } else { })
                    excludeGroups = @(if ($policyDetail.Conditions.Users.ExcludeGroups) { $policyDetail.Conditions.Users.ExcludeGroups } else { })
                }

                # Update roles based on operation
                if ($Operation -eq 'Include') {
                    $usersCondition['includeRoles'] = @($selectedRoles.Id)
                    $usersCondition['excludeRoles'] = @(if ($policyDetail.Conditions.Users.ExcludeRoles) { $policyDetail.Conditions.Users.ExcludeRoles } else { })
                }
                else {
                    $usersCondition['excludeRoles'] = @($selectedRoles.Id)
                    $usersCondition['includeRoles'] = @(if ($policyDetail.Conditions.Users.IncludeRoles) { $policyDetail.Conditions.Users.IncludeRoles } else { })
                }



                   # Build the body parameter with updated display name
                   $bodyParams = @{
                    displayName = $newDisplayName
                    Conditions  = @{
                        Users = $usersCondition
                    }
                }

                # Update policy using MgBeta cmdlet
                $null = Update-MgBetaIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $policy.Id -BodyParameter $bodyParams

                $null = $results.Add([PSCustomObject]@{
                        PolicyName   = $policy.DisplayName
                        PolicyId     = $policy.Id
                        Operation    = $Operation
                        RolesUpdated = ($selectedRoles.DisplayName -join ', ')
                        RoleCount    = $selectedRoles.Count
                        Status       = 'Success'
                        ErrorMessage = ''
                    })

                Write-Host "Successfully updated policy: $($policy.DisplayName)" -ForegroundColor Green
            }
            catch {
                $errorMessage = if ($_.ErrorDetails.Message) {
                    $_.ErrorDetails.Message
                }
                else {
                    $_.Exception.Message
                }

                $null = $results.Add([PSCustomObject]@{
                        PolicyName   = $policy.DisplayName
                        PolicyId     = $policy.Id
                        Operation    = $Operation
                        RolesUpdated = ''
                        RoleCount    = 0
                        Status       = 'Failed'
                        ErrorMessage = $errorMessage
                    })
                
                Write-Warning "Failed to update policy $($policy.DisplayName): $errorMessage"
            }
        }
        
        if ($results.Count -gt 0) {
            $reportPaths = Export-AdminRolesReport -Results $results -OutputDir $OutputPath
            
            Write-Host "`nOperation Complete!" -ForegroundColor Green
            Write-Host "Summary:" -ForegroundColor Cyan
            Write-Host "- Total Policies Processed: $($results.Count)" -ForegroundColor White
            Write-Host "- Successful Updates: $(($results | Where-Object Status -eq 'Success').Count)" -ForegroundColor White
            Write-Host "- Failed Updates: $(($results | Where-Object Status -eq 'Failed').Count)" -ForegroundColor White
            Write-Host "`nDetailed reports have been generated at:" -ForegroundColor Cyan
            Write-Host "CSV Report: $($reportPaths.CSVPath)" -ForegroundColor White
            Write-Host "HTML Report: $($reportPaths.HTMLPath)" -ForegroundColor White
        }
        
        return $results
    }
    catch {
        Write-Error "Operation failed: $_"
    }
}

Update-ConditionalAccessPolicyAdminRoles