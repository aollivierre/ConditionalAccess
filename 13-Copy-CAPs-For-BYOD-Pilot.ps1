# Function definitions
function Test-PolicyJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )
    
    try {
        $null = Get-Content $FilePath -Raw | ConvertFrom-Json
        return @{
            IsValid = $true
            Error = $null
        }
    }
    catch {
        return @{
            IsValid = $false
            Error = $_.Exception.Message
        }
    }
}

function Test-PolicyFiles {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$SourcePath,
        
        [Parameter(Mandatory)]
        [string[]]$ExpectedPolicies
    )
    
    $results = [System.Collections.ArrayList]::new()
    
    foreach ($policy in $ExpectedPolicies) {
        $policyPath = Join-Path $SourcePath "$policy.json"
        $exists = Test-Path $policyPath
        
        $resultObject = [PSCustomObject]@{
            PolicyName = $policy
            Exists = $exists
            FullPath = $policyPath
            IsValidJson = $false
            JsonError = $null
        }
        
        if ($exists) {
            $jsonTest = Test-PolicyJson -FilePath $policyPath
            $resultObject.IsValidJson = $jsonTest.IsValid
            $resultObject.JsonError = $jsonTest.Error
        }
        
        $null = $results.Add($resultObject)
    }
    
    return $results
}

function Copy-PolicyFiles {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$SourcePath,
        
        [Parameter(Mandatory)]
        [string]$DestinationPath,
        
        [Parameter(Mandatory)]
        [string[]]$Policies
    )
    
    $results = [System.Collections.ArrayList]::new()
    
    foreach ($policy in $Policies) {
        try {
            $sourceFile = Join-Path $SourcePath "$policy.json"
            Copy-Item -Path $sourceFile -Destination $DestinationPath -Force -ErrorAction Stop
            
            $resultObject = [PSCustomObject]@{
                PolicyName = $policy
                Status = 'Success'
                ErrorMessage = ''
            }
        }
        catch {
            $resultObject = [PSCustomObject]@{
                PolicyName = $policy
                Status = 'Failed'
                ErrorMessage = $_.Exception.Message
            }
        }
        
        $null = $results.Add($resultObject)
    }
    
    return $results
}

function Export-PolicyCopyReport {
    param(
        [Parameter(Mandatory)]
        $Results,
        
        [Parameter(Mandatory)]
        [string]$OutputDir,
        
        [Parameter()]
        [string]$ReportName = "PolicyCopy_Report"
    )
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $htmlPath = Join-Path $OutputDir "$($ReportName)_$timestamp.html"
    $csvPath = Join-Path $OutputDir "$($ReportName)_$timestamp.csv"
    
    # Export to CSV
    $Results | Export-Csv -Path $csvPath -NoTypeInformation
    
    $metadata = @{
        GeneratedBy = $env:USERNAME
        GeneratedOn = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        TotalPolicies = $Results.Count
        SuccessCount = ($Results | Where-Object Status -eq "Success").Count
        FailureCount = ($Results | Where-Object Status -eq "Failed").Count
    }
    
    New-HTML -Title "Policy Copy Report" -FilePath $htmlPath -ShowHTML {
        New-HTMLSection -HeaderText "Copy Operation Summary" {
            New-HTMLPanel {
                New-HTMLText -Text @"
                <h3>Report Details</h3>
                <ul>
                    <li>Generated By: $($metadata.GeneratedBy)</li>
                    <li>Generated On: $($metadata.GeneratedOn)</li>
                    <li>Total Policies: $($metadata.TotalPolicies)</li>
                    <li>Successful Copies: $($metadata.SuccessCount)</li>
                    <li>Failed Copies: $($metadata.FailureCount)</li>
                </ul>
"@
            }
        }
        
        New-HTMLSection -HeaderText "Policy Copy Results" {
            New-HTMLTable -DataTable $Results -ScrollX -Buttons @('copyHtml5', 'excelHtml5', 'csvHtml5') -SearchBuilder {
                New-TableCondition -Name 'Status' -ComparisonType string -Operator eq -Value 'Failed' -BackgroundColor Salmon -Color Black
                New-TableCondition -Name 'Status' -ComparisonType string -Operator eq -Value 'Success' -BackgroundColor LightGreen -Color Black
            }
        }
    }

    Write-Host "`nReports generated:" -ForegroundColor Green
    Write-Host "CSV Report: $csvPath" -ForegroundColor Green
    Write-Host "HTML Report: $htmlPath" -ForegroundColor Green
    
    return @{
        CSVPath = $csvPath
        HTMLPath = $htmlPath
    }
}

function Copy-ConditionalAccessPolicies {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$SourcePath,
        
        [Parameter(Mandatory)]
        [string]$BaseDestPath,
        
        [Parameter(Mandatory)]
        [string[]]$ExpectedPolicies
    )
    
    # Create timestamp for destination folder
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $destPath = Join-Path $BaseDestPath "BYOD-Pilot-CAPs-$timestamp"
    
    # Test policy files
    $fileCheck = Test-PolicyFiles -SourcePath $SourcePath -ExpectedPolicies $ExpectedPolicies
    $missingFiles = $fileCheck | Where-Object { -not $_.Exists }
    $invalidJsonFiles = $fileCheck | Where-Object { $_.Exists -and -not $_.IsValidJson }
    
    $hasErrors = $false
    
    if ($missingFiles) {
        Write-Error "Missing policy files:"
        $missingFiles | ForEach-Object { 
            Write-Error "- $($_.PolicyName)" 
        }
        $hasErrors = $true
    }
    
    if ($invalidJsonFiles) {
        Write-Error "Invalid JSON found in policy files:"
        $invalidJsonFiles | ForEach-Object { 
            Write-Error "- $($_.PolicyName): $($_.JsonError)" 
        }
        $hasErrors = $true
    }
    
    if ($hasErrors) {
        return
    }
    
    # Create destination directory
    try {
        $null = New-Item -ItemType Directory -Path $destPath -Force
        Write-Host "Created destination directory: $destPath" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to create destination directory: $_"
        return
    }
    
    # Copy files and generate report
    $copyResults = Copy-PolicyFiles -SourcePath $SourcePath -DestinationPath $destPath -Policies $ExpectedPolicies
    Export-PolicyCopyReport -Results $copyResults -OutputDir $destPath
    
    return $copyResults
}

# Define paths and policies
$sourcePath = "C:\CaaC\SandBox\Dec182024-v5\DC_KVS_AO_Combined\MSFT\ConditionalAccess"
$baseDestPath = "C:\CaaC\SandBox"
$expectedPolicies = @(
    "CAD004-O365 Grant Require MFA for All users when Browser and Non-Compliant-v1.5",
    "CAD005-O365 Block access for unsupported device platforms for All users when Modern Auth Clients-v1.2",
    "CAD006-O365 Session block download on unmanaged device for All users when Browser and Modern App Clients and Non-Compliant-v1.5",
    "CAD007-O365 Session set Sign-in Frequency for Apps for All users when Modern Auth Clients and Non-Compliant-v1.2",
    "GLOBAL - 3020 - SESSION - BYOD Persistence",
    "CAD010-RJD Require MFA for device join or registration when Browser and Modern Auth Clients-v1.2",
    "CAL002-RSI Require MFA registration from trusted locations only for All users when Browser and Modern Auth Clients-v1.5",
    "CAP002-O365 Grant Exchange ActiveSync Clients for All users when Approved App-v1.0",
    "CAU009-Management BLOCK Admin Portals for All Users when Browser and Modern Auth Clients-v1.2",
    "GLOBAL - 1020 - BLOCK - Device Code Auth Flow",
    "GLOBAL - 1060 - BLOCK - Service Accounts (Trusted Locations Excluded) - Remember to add 1 service account per policy",
    "GLOBAL - 1080 - BLOCK - Guest Access to Sensitive Apps",
    "GLOBAL - 3030 - SESSION - Register Security Info Requirements - v1.2",
    "CAD001-O365 Grant macOS access for All users when Modern Auth Clients and Compliant-v1.1",
    "CAD002-O365 Grant Windows access for All users when Modern Auth Clients and Compliant-v1.1",
    "CAD003-O365 Grant iOS and Android access for All users when Modern Auth Clients and ApprovedApp or Compliant-v1.2",
    "CAD011-O365 Grant Linux access for All users when Modern Auth Clients and Compliant-v1.0",
    "GLOBAL - 2070 - GRANT - Mobile Device Access Requirements - v1.2",
    "CAD014-O365 Require App Protection Policy for Edge on Windows for All users when Browser and Non-Compliant-v1.0"
)

# Execute the copy operation
Copy-ConditionalAccessPolicies -SourcePath $sourcePath -BaseDestPath $baseDestPath -ExpectedPolicies $expectedPolicies
