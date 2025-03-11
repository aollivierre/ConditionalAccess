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