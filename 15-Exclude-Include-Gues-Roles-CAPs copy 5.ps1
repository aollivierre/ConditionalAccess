#Requires -Modules Microsoft.Graph.Identity.SignIns, PSWriteHTML


function Get-ConditionalAccessPoliciesDetails {
    [CmdletBinding()]
    param()
    
    try {
        Write-Verbose "Retrieving policies from Microsoft Graph..."
        $policies = Get-MgIdentityConditionalAccessPolicy -All
        
        if (-not $policies) {
            Write-Warning "No policies retrieved from Microsoft Graph"
            return @()
        }

        Write-Verbose "Processing $($policies.Count) policies..."
        $formattedPolicies = @(foreach ($policy in $policies) {
                Write-Verbose "Processing policy: $($policy.DisplayName)"
            
                # Extract current version from display name
                $version = if ($policy.DisplayName -match '-v(\d+\.\d+)$') {
                    [decimal]$matches[1]
                }
                else {
                    1.0
                }
            
                # Build the guest status string
                $guestStatus = @()
            
                if ($policy.Conditions.Users.IncludeGuestsOrExternalUsers) {
                    $guestStatus += "Include: Guest/External Users"
                }
            
                if ($policy.Conditions.Users.ExcludeGuestsOrExternalUsers) {
                    $guestStatus += "Exclude: Guest/External Users"
                }
            
                $currentGuestStatus = if ($guestStatus.Count -gt 0) {
                    $guestStatus -join ' | '
                }
                else {
                    "No guest configuration"
                }
            
                # Create and output the object
                [PSCustomObject]@{
                    DisplayName        = $policy.DisplayName
                    Id                 = $policy.Id
                    State              = $policy.State
                    Version            = $version
                    CurrentGuestStatus = $currentGuestStatus
                }
            })

        Write-Verbose "Returning $($formattedPolicies.Count) formatted policies"
        return $formattedPolicies
    }
    catch {
        Write-Error "Failed to retrieve or process Conditional Access Policies: $_"
        return @()
    }
}


function Export-GuestPolicyReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Results,
        
        [Parameter(Mandatory)]
        [string]$OutputDir,
        
        [Parameter()]
        [string]$ReportName = "GuestPolicy_Update"
    )
    
    $reportParams = @{
        OutputDir  = $OutputDir
        ReportName = $ReportName
        Results    = $Results
        Timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
    }

    $reportPaths = @{
        HTML = Join-Path $OutputDir "$($ReportName)_$($reportParams.Timestamp).html"
        CSV  = Join-Path $OutputDir "$($ReportName)_$($reportParams.Timestamp).csv"
    }

    # Ensure output directory exists
    $null = New-Item -ItemType Directory -Force -Path $OutputDir

    # Export to CSV
    $Results | Export-Csv -Path $reportPaths.CSV -NoTypeInformation

    # Generate HTML report
    New-HTML -TitleText "Guest Policy Update Report" -FilePath $reportPaths.HTML -ShowHTML {
        New-HTMLSection -HeaderText "Policy Update Summary" {
            New-HTMLPanel {
                New-HTMLText -Text @"
                <h3>Update Details</h3>
                <ul>
                    <li>Total Policies Updated: $($Results.Count)</li>
                    <li>Successful Updates: $($Results.Where{$_.Status -eq 'Success'}.Count)</li>
                    <li>Failed Updates: $($Results.Where{$_.Status -eq 'Failed'}.Count)</li>
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
    Write-Host "CSV Report: $($reportPaths.CSV)" -ForegroundColor Green
    Write-Host "HTML Report: $($reportPaths.HTML)" -ForegroundColor Green

    return $reportPaths
}


function Get-GuestUserTypes {
    [CmdletBinding()]
    param()
    
    # Define guest types directly in the array to avoid blank rows
    $guestTypes = @(
        [PSCustomObject]@{
            DisplayName = "B2B collaboration guest users"
            Id = "b2bCollaborationGuest"
            Description = "Users who are invited to collaborate with your organization"
            Category = "B2B"
        },
        [PSCustomObject]@{
            DisplayName = "B2B collaboration member users"
            Id = "b2bCollaborationMember"
            Description = "Members from other organizations collaborating with yours"
            Category = "B2B"
        },
        [PSCustomObject]@{
            DisplayName = "B2B direct connect users"
            Id = "b2bDirectConnectUser"
            Description = "Users connecting directly from partner organizations"
            Category = "B2B"
        },
        [PSCustomObject]@{
            DisplayName = "Local guest users"
            Id = "localGuest"
            Description = "Guest users created within your organization"
            Category = "Local"
        },
        [PSCustomObject]@{
            DisplayName = "Service provider users"
            Id = "serviceProvider"
            Description = "Users from service provider organizations"
            Category = "External"
        },
        [PSCustomObject]@{
            DisplayName = "Other external users"
            Id = "otherExternalUser"
            Description = "All other types of external users"
            Category = "External"
        }
    ) | Sort-Object Category, DisplayName
    
    return $guestTypes
}


function Update-ConditionalAccessPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Policy,
        
        [Parameter(Mandatory)]
        [ValidateSet('Include', 'Exclude')]
        [string]$Operation,
        
        [Parameter(Mandatory)]
        [object[]]$GuestTypes
    )
    
    try {
        Write-Host "Step 1: Retrieving current policy..." -ForegroundColor Cyan
        $currentPolicy = Get-MgBetaIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $Policy.Id
        
        if (-not $currentPolicy) {
            throw "Failed to retrieve current policy"
        }

        # Format guest types as a comma-separated string
        $guestTypesString = $GuestTypes.Id -join ','
        if ($guestTypesString -notlike '*internalGuest*') {
            $guestTypesString = "internalGuest,$guestTypesString"
        }

        # Preserve existing policy settings
        $bodyParams = @{
            displayName = if ($Policy.DisplayName -match '-v\d+\.\d+$') {
                $Policy.DisplayName -replace '-v\d+\.\d+$', "-v$($Policy.Version + 0.1)"
            }
            else {
                "$($Policy.DisplayName)-v$($Policy.Version + 0.1)"
            }
            state = $currentPolicy.State
            conditions = @{
                clientAppTypes = $currentPolicy.Conditions.ClientAppTypes
                applications = @{
                    includeApplications = $currentPolicy.Conditions.Applications.IncludeApplications
                    excludeApplications = $currentPolicy.Conditions.Applications.ExcludeApplications
                }
                users = @{
                    includeUsers = $currentPolicy.Conditions.Users.IncludeUsers
                    excludeUsers = $currentPolicy.Conditions.Users.ExcludeUsers
                    includeGroups = $currentPolicy.Conditions.Users.IncludeGroups
                    excludeGroups = $currentPolicy.Conditions.Users.ExcludeGroups
                    excludeRoles = $currentPolicy.Conditions.Users.ExcludeRoles
                }
                devices = $currentPolicy.Conditions.Devices
            }
            grantControls = @{
                operator = $currentPolicy.GrantControls.Operator
                builtInControls = @()
                authenticationStrength = @{
                    id = "00000000-0000-0000-0000-000000000004"
                }
            }
            sessionControls = @{
                signInFrequency = @{
                    isEnabled = $true
                    type = $null
                    value = $null
                    frequencyInterval = "everyTime"
                    authenticationType = "primaryAndSecondaryAuthentication"
                }
                persistentBrowser = @{
                    isEnabled = $true
                    mode = "never"
                }
            }
        }

        # Add guest configuration based on operation
        $guestConfig = @{
            guestOrExternalUserTypes = $guestTypesString
            externalTenants = @{
                membershipKind = "all"
            }
        }

        if ($Operation -eq 'Include') {
            $bodyParams.conditions.users['includeGuestsOrExternalUsers'] = $guestConfig
            $bodyParams.conditions.users.Remove('excludeGuestsOrExternalUsers')
        }
        else {
            $bodyParams.conditions.users['excludeGuestsOrExternalUsers'] = $guestConfig
            $bodyParams.conditions.users.Remove('includeGuestsOrExternalUsers')
        }

        Write-Host "`nUpdating policy..." -ForegroundColor Cyan
        Write-Verbose "Update body: $(ConvertTo-Json $bodyParams -Depth 10)"

        $params = @{
            ConditionalAccessPolicyId = $Policy.Id
            BodyParameter = $bodyParams
            ErrorAction = 'Stop'
        }
        
        $null = Update-MgBetaIdentityConditionalAccessPolicy @params
        Write-Host "Policy updated successfully" -ForegroundColor Green
        
        return $true
    }
    catch {
        Write-Error -ErrorRecord $_
        Write-Host "`nError updating policy: $($_.Exception.Message)" -ForegroundColor Red
        
        if ($_.Exception.Response) {
            $response = $_.Exception.Response
            Write-Host "Status Code: $($response.StatusCode)" -ForegroundColor Red
            Write-Host "Status Description: $($response.StatusDescription)" -ForegroundColor Red
        }
        
        return $false
    }
}


function Update-ConditionalAccessPolicyGuestTypes {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$OutputPath = ".\Reports"
    )
    
    try {
        # Show welcome message
        Write-Host "`nConditional Access Policy Guest Types Update Tool" -ForegroundColor Cyan
        Write-Host "=================================================" -ForegroundColor Cyan
        
        # Get operation choice
        $operation = Show-GuestOperationMenu
        if ($operation -eq 'Cancel') {
            Write-Host "`nOperation cancelled by user." -ForegroundColor Yellow
            return
        }
        
        Write-Host "`nSelected Operation: $operation" -ForegroundColor Green

        # Get policies
        Write-Host "`nRetrieving current policy information..." -ForegroundColor Cyan
        $policies = Get-ConditionalAccessPoliciesDetails
        if (-not $policies) { 
            Write-Warning "No policies found to process."
            return 
        }
                
        $selectedPolicies = $policies | 
        Out-GridView -Title "Select Conditional Access Policies to Modify" -PassThru
                
        if (-not $selectedPolicies) {
            Write-Warning "No policies selected for processing."
            return
        }

        # Select guest types
        Write-Host "`nSelect guest types to $($operation.ToLower())..." -ForegroundColor Cyan
        $guestTypes = @(
            [PSCustomObject]@{
                Name = "Internal guest users"
                Id = "internalGuest"
                Description = "Guest users within your organization"
            },
            [PSCustomObject]@{
                Name = "B2B collaboration guest users"
                Id = "b2bCollaborationGuest"
                Description = "Users invited to collaborate with your organization"
            },
            [PSCustomObject]@{
                Name = "B2B collaboration member users"
                Id = "b2bCollaborationMember"
                Description = "Members from other organizations"
            },
            [PSCustomObject]@{
                Name = "B2B direct connect users"
                Id = "b2bDirectConnectUser"
                Description = "Users connecting directly from partner organizations"
            },
            [PSCustomObject]@{
                Name = "Other external users"
                Id = "otherExternalUser"
                Description = "All other types of external users"
            },
            [PSCustomObject]@{
                Name = "Service provider users"
                Id = "serviceProvider"
                Description = "Users from service provider organizations"
            }
        )

        $selectedGuestTypes = $guestTypes | 
            Out-GridView -Title "Select Guest Types to $operation" -PassThru
        
        if (-not $selectedGuestTypes) {
            Write-Warning "No guest types selected. Operation cancelled."
            return
        }

        # Enhanced operation summary
        Write-Host "`nOperation Summary:" -ForegroundColor Cyan
        Write-Host "==================" -ForegroundColor Cyan
        Write-Host "Operation: $operation guest/external users" -ForegroundColor White
        Write-Host "`nSelected Policies:" -ForegroundColor White
        $selectedPolicies | ForEach-Object { Write-Host "- $($_.DisplayName)" -ForegroundColor Gray }
        Write-Host "`nSelected Guest Types:" -ForegroundColor White
        $selectedGuestTypes | ForEach-Object { Write-Host "- $($_.Name)" -ForegroundColor Gray }
        
        $confirm = Read-Host "`nDo you want to proceed? [Y/N]"
        if ($confirm -notmatch '^[Yy]$') {
            Write-Host "`nOperation cancelled by user." -ForegroundColor Yellow
            return
        }
        
        $results = [System.Collections.ArrayList]::new()
        
        foreach ($policy in $selectedPolicies) {
            try {
                Write-Host "`nProcessing policy: $($policy.DisplayName)" -ForegroundColor Cyan
                
                # Create update body
                $bodyParams = @{
                    conditions = @{
                        users = @{
                            "$($operation.ToLower())GuestsOrExternalUsers" = @{
                                guestOrExternalUserTypes = $selectedGuestTypes.Id -join ','
                                externalTenants = @{
                                    membershipKind = "all"
                                }
                            }
                        }
                    }
                }

                # Update policy
                $null = Update-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $policy.Id -BodyParameter $bodyParams
                
                $null = $results.Add([PSCustomObject]@{
                    PolicyName = $policy.DisplayName
                    PolicyId = $policy.Id
                    Operation = $operation
                    GuestTypesUpdated = $selectedGuestTypes.Name -join ', '
                    Status = 'Success'
                    ErrorMessage = ''
                })

                Write-Host "Successfully updated policy: $($policy.DisplayName)" -ForegroundColor Green
            }
            catch {
                $errorMessage = $_.Exception.Message
                
                $null = $results.Add([PSCustomObject]@{
                    PolicyName = $policy.DisplayName
                    PolicyId = $policy.Id
                    Operation = $operation
                    GuestTypesUpdated = ''
                    Status = 'Failed'
                    ErrorMessage = $errorMessage
                })
                
                Write-Warning "Failed to update policy $($policy.DisplayName): $errorMessage"
            }
        }
        
        if ($results.Count -gt 0) {
            Export-GuestPolicyReport -Results $results -OutputDir $OutputPath
        }
        
        return $results
    }
    catch {
        Write-Error "Operation failed: $_"
    }
}

function Show-GuestOperationMenu {
    [CmdletBinding()]
    param()
    
    $menuText = @"

====== Conditional Access Policy Guest Operation ======

Select an operation:
[I] Include Selected Guest Types
[E] Exclude Selected Guest Types
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




# Main execution
Update-ConditionalAccessPolicyGuestTypes