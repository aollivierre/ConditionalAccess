# Requires -Modules Microsoft.Graph.Groups, PSWriteHTML

function Get-RecentEntraGroups {
    [CmdletBinding()]
    param (
        [int]$HoursBack = 2
    )
    
    $groups = [System.Collections.Generic.List[PSCustomObject]]::new()
    $filterDate = (Get-Date).AddHours(-$HoursBack).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    Write-Verbose "Filtering groups created after: $filterDate"
    
    # Build query components
    $baseUri = "https://graph.microsoft.com/v1.0/groups"
    $filter = "`$filter=createdDateTime ge $filterDate"
    $select = "`$select=id,displayName,description,createdDateTime,mailEnabled,securityEnabled,mailNickname,groupTypes"
    $orderBy = "`$orderby=createdDateTime desc"
    
    # URL encode the components
    $encodedFilter = [System.Web.HttpUtility]::UrlEncode($filter)
    $encodedSelect = [System.Web.HttpUtility]::UrlEncode($select)
    $encodedOrderBy = [System.Web.HttpUtility]::UrlEncode($orderBy)
    
    $uri = "$baseUri`?$encodedFilter&$encodedSelect&$encodedOrderBy"
    
    do {
        try {
            Write-Verbose "Executing request: $uri"
            $response = Invoke-MgGraphRequest -Uri $uri -Method GET -Headers @{
                "ConsistencyLevel" = "eventual"
                "Prefer" = "odata.maxpagesize=999"
            }
            
            if ($response.value) {
                foreach ($group in $response.value) {
                    $createdDate = [DateTime]$group.createdDateTime
                    if ($createdDate -ge (Get-Date).AddHours(-$HoursBack)) {
                        # Determine group type
                        $groupType = if ($group.mailEnabled) { 
                            if ($group.groupTypes -contains "Unified") { "Microsoft 365" }
                            else { "Distribution" }
                        } else { 
                            if ($group.securityEnabled) { "Security" }
                            else { "Other" }
                        }

                        # Create formatted group object
                        $formattedGroup = [PSCustomObject]@{
                            DisplayName = $group.displayName
                            Description = $group.description
                            CreatedDateTime = $createdDate
                            Id = $group.id
                            Type = $groupType
                            MailNickname = $group.mailNickname
                            GroupTypes = ($group.groupTypes -join ', ')
                            MailEnabled = $group.mailEnabled
                            SecurityEnabled = $group.securityEnabled
                        }
                        [void]$groups.Add($formattedGroup)
                    }
                }
            }
            
            $uri = $response.'@odata.nextLink'
        }
        catch {
            Write-Error "Failed to retrieve groups: $_"
            Write-Verbose "Full error details: $($_.Exception.Message)"
            return $null
        }
    } while ($uri)
    
    Write-Verbose "Found $($groups.Count) groups created in the last $HoursBack hour(s)"
    Write-Output $groups
}

function Export-GroupDeletionReport {
    param(
        [Parameter(Mandatory)]
        $Groups,
        [Parameter(Mandatory)]
        [string]$OutputDir
    )
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $htmlPath = Join-Path $OutputDir "GroupDeletionReport_$timestamp.html"
    $csvPath = Join-Path $OutputDir "GroupDeletionReport_$timestamp.csv"
    
    # Export to CSV
    $Groups | Export-Csv -Path $csvPath -NoTypeInformation
    
    $metadata = @{
        GeneratedBy = $env:USERNAME
        GeneratedOn = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        TotalGroups = $Groups.Count
        SecurityGroups = ($Groups | Where-Object { $_.Type -eq 'Security' }).Count
        M365Groups = ($Groups | Where-Object { $_.Type -eq 'Microsoft 365' }).Count
        DistributionGroups = ($Groups | Where-Object { $_.Type -eq 'Distribution' }).Count
    }
    
    New-HTML -TitleText "Group Deletion Report" -FilePath $htmlPath -ShowHTML {
        New-HTMLSection -HeaderText "Group Deletion Report - $(Get-Date -Format 'yyyy-MM-dd HH:mm')" {
            New-HTMLPanel {
                New-HTMLText -Text @"
                <h3>Report Details</h3>
                <ul>
                    <li>Generated By: $($metadata.GeneratedBy)</li>
                    <li>Generated On: $($metadata.GeneratedOn)</li>
                    <li>Total Groups: $($metadata.TotalGroups)</li>
                    <li>Security Groups: $($metadata.SecurityGroups)</li>
                    <li>Microsoft 365 Groups: $($metadata.M365Groups)</li>
                    <li>Distribution Groups: $($metadata.DistributionGroups)</li>
                </ul>
"@
            }
        }
        
        New-HTMLSection -HeaderText "Groups Pending Deletion" -CanCollapse {
            New-HTMLTable -DataTable $Groups -ScrollX {
                New-TableCondition -Name 'Type' -ComparisonType string -Operator eq -Value 'Microsoft 365' -BackgroundColor '#BDE2FF' -Color Black
                New-TableCondition -Name 'Type' -ComparisonType string -Operator eq -Value 'Security' -BackgroundColor '#C2F0C2' -Color Black
                New-TableCondition -Name 'Type' -ComparisonType string -Operator eq -Value 'Distribution' -BackgroundColor '#FFE2B2' -Color Black
            } -Buttons @('copyHtml5', 'excelHtml5', 'csvHtml5', 'searchBuilder')
        }
    }

    return @{
        CSVPath = $csvPath
        HTMLPath = $htmlPath
    }
}

function Remove-EntraGroupsSafely {
    param (
        [Parameter(Mandatory)]
        [object[]]$Groups
    )
    
    # Create output directory
    $outputDir = ".\GroupDeletionReports"
    $null = New-Item -ItemType Directory -Force -Path $outputDir

    # Generate initial reports
    $reports = Export-GroupDeletionReport -Groups $Groups -OutputDir $outputDir
    
    Write-Host "`nReports generated:" -ForegroundColor Green
    Write-Host "CSV Report: $($reports.CSVPath)" -ForegroundColor Green
    Write-Host "HTML Report: $($reports.HTMLPath)" -ForegroundColor Green

    # Display summary counts
    Write-Host "`nGroup Summary:" -ForegroundColor Cyan
    $groupCounts = $Groups | Group-Object Type | Sort-Object Count -Descending
    foreach ($groupType in $groupCounts) {
        Write-Host "$($groupType.Name) groups: $($groupType.Count)" -ForegroundColor Yellow
    }

    # Display detailed table
    Write-Host "`nGroups to be deleted:" -ForegroundColor Cyan
    $Groups | Sort-Object Type, DisplayName | Format-Table -AutoSize @(
        @{
            Name = 'DisplayName'
            Expression = { $_.DisplayName }
            Width = 50
        }
        @{
            Name = 'Type'
            Expression = { $_.Type }
            Width = 15
        }
        @{
            Name = 'Created'
            Expression = { $_.CreatedDateTime.ToString('MM/dd HH:mm') }
            Width = 14
        }
        @{
            Name = 'MailNickname'
            Expression = { $_.MailNickname }
            Width = 20
        }
        @{
            Name = 'Description'
            Expression = { 
                if ($_.Description.Length -gt 50) {
                    "$($_.Description.Substring(0, 47))..."
                } else {
                    $_.Description
                }
            }
            Width = 50
        }
    )

    # Ask for confirmation
    $confirmation = Read-Host "`nDo you want to proceed with deleting these groups? (Y/N)"
    
    if ($confirmation -eq 'Y') {
        $deleted = [System.Collections.ArrayList]::new()
        $failed = [System.Collections.ArrayList]::new()

        foreach ($group in $Groups) {
            try {
                $deleteUri = "https://graph.microsoft.com/v1.0/groups/$($group.Id)"
                Invoke-MgGraphRequest -Uri $deleteUri -Method DELETE
                [void]$deleted.Add($group)
                Write-Host "Deleted group: $($group.DisplayName)" -ForegroundColor Green
            }
            catch {
                [void]$failed.Add(@{
                    Group = $group.DisplayName
                    Type = $group.Type
                    Error = $_.Exception.Message
                })
                Write-Host "Failed to delete group $($group.DisplayName): $_" -ForegroundColor Red
            }
        }

        # Generate results report
        $resultsPath = Join-Path $outputDir "DeletionResults_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
        New-HTML -TitleText "Group Deletion Results" -FilePath $resultsPath -ShowHTML {
            New-HTMLSection -HeaderText "Deletion Results Summary" {
                New-HTMLPanel {
                    New-HTMLText -Text @"
                    <h3>Operation Summary</h3>
                    <ul>
                        <li>Successfully deleted: $($deleted.Count)</li>
                        <li>Failed deletions: $($failed.Count)</li>
                        <li>Completed at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</li>
                    </ul>
"@
                }
            }
            if ($deleted.Count -gt 0) {
                New-HTMLSection -HeaderText "Successfully Deleted Groups" -CanCollapse {
                    New-HTMLTable -DataTable $deleted -ScrollX
                }
            }
            if ($failed.Count -gt 0) {
                New-HTMLSection -HeaderText "Failed Deletions" -CanCollapse {
                    New-HTMLTable -DataTable $failed -ScrollX
                }
            }
        }
    }
    else {
        Write-Host "Operation cancelled by user." -ForegroundColor Yellow
    }
}

function Start-EntraGroupCleanup {
    [CmdletBinding()]
    param()
    
    # Add System.Web for URL encoding
    Add-Type -AssemblyName System.Web
    
    # Connect to Microsoft Graph if not already connected
    try {
        $context = Get-MgContext -ErrorAction Stop
        Write-Host "Connected to Microsoft Graph as: $($context.Account)" -ForegroundColor Green
    }
    catch {
        Write-Host "Please connect to Microsoft Graph first using Connect-MgGraph -Scopes 'Group.ReadWrite.All'" -ForegroundColor Yellow
        return
    }

    $recentGroups = Get-RecentEntraGroups -Verbose
    
    if ($null -eq $recentGroups) {
        Write-Host "No groups found or error occurred." -ForegroundColor Yellow
        return
    }
    
    if ($recentGroups.Count -eq 0) {
        Write-Host "No groups found created in the past hour." -ForegroundColor Green
        return
    }
    
    Remove-EntraGroupsSafely -Groups $recentGroups
}

# Connect-MgGraph -Scopes "Group.ReadWrite.All"
Start-EntraGroupCleanup -Verbose