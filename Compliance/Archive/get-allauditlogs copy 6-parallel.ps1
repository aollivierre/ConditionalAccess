#############################################################################################################
#
#   Tool:           Intune Win32 Deployer
#   Author:         Abdullah Ollivierre
#   Website:        https://github.com/aollivierre
#   Twitter:        https://x.com/ollivierre
#   LinkedIn:       https://www.linkedin.com/in/aollivierre
#
#   Description:    https://github.com/aollivierre
#
#############################################################################################################

<#
    .SYNOPSIS
    Packages any custom app for MEM (Intune) deployment.
    Uploads the packaged into the target Intune tenant.

    .NOTES
    For details on IntuneWin32App go here: https://github.com/aollivierre

#>

#################################################################################################################################
################################################# START VARIABLES ###############################################################
#################################################################################################################################

#First, load secrets and create a credential object:
# Assuming secrets.json is in the same directory as your script
$secretsPath = Join-Path -Path $PSScriptRoot -ChildPath "secrets.json"

# Load the secrets from the JSON file
$secrets = Get-Content -Path $secretsPath -Raw | ConvertFrom-Json

# Read configuration from the JSON file
# Assign values from JSON to variables

# Read configuration from the JSON file
$configPath = Join-Path -Path $PSScriptRoot -ChildPath "config.json"
$env:MYMODULE_CONFIG_PATH = $configPath

$config = Get-Content -Path $configPath -Raw | ConvertFrom-Json

#  Variables from JSON file
$tenantId = $secrets.tenantId
$clientId = $secrets.clientId

$certPath = Join-Path -Path $PSScriptRoot -ChildPath 'graphcert.pfx'
$CertPassword = $secrets.CertPassword


function Initialize-Environment {
    param (
        [string]$WindowsModulePath = "EnhancedBoilerPlateAO\2.0.0\EnhancedBoilerPlateAO.psm1",
        [string]$LinuxModulePath = "/usr/src/code/Modules/EnhancedBoilerPlateAO/2.0.0/EnhancedBoilerPlateAO.psm1"
    )

    function Get-Platform {
        if ($PSVersionTable.PSVersion.Major -ge 7) {
            return $PSVersionTable.Platform
        }
        else {
            return [System.Environment]::OSVersion.Platform
        }
    }

    function Setup-GlobalPaths {
        if ($env:DOCKER_ENV -eq $true) {
            $global:scriptBasePath = $env:SCRIPT_BASE_PATH
            $global:modulesBasePath = $env:MODULES_BASE_PATH
        }
        else {
            $global:scriptBasePath = $PSScriptRoot
            $global:modulesBasePath = "$PSScriptRoot\modules"
        }
    }

    function Setup-WindowsEnvironment {
        # Get the base paths from the global variables
        Setup-GlobalPaths

        # Construct the paths dynamically using the base paths
        $global:modulePath = Join-Path -Path $modulesBasePath -ChildPath $WindowsModulePath
        $global:AOscriptDirectory = Join-Path -Path $scriptBasePath -ChildPath "Win32Apps-DropBox"
        $global:directoryPath = Join-Path -Path $scriptBasePath -ChildPath "Win32Apps-DropBox"
        $global:Repo_Path = $scriptBasePath
        $global:Repo_winget = "$Repo_Path\Win32Apps-DropBox"


        # Import the module using the dynamically constructed path
        Import-Module -Name $global:modulePath -Verbose -Force:$true -Global:$true

        # Log the paths to verify
        Write-Output "Module Path: $global:modulePath"
        Write-Output "Repo Path: $global:Repo_Path"
        Write-Output "Repo Winget Path: $global:Repo_winget"
    }

    function Setup-LinuxEnvironment {
        # Get the base paths from the global variables
        Setup-GlobalPaths

        # Import the module using the Linux path
        Import-Module $LinuxModulePath -Verbose

        # Convert paths from Windows to Linux format
        $global:AOscriptDirectory = Convert-WindowsPathToLinuxPath -WindowsPath "C:\Users\Admin-Abdullah\AppData\Local\Intune-Win32-Deployer"
        $global:directoryPath = Convert-WindowsPathToLinuxPath -WindowsPath "C:\Users\Admin-Abdullah\AppData\Local\Intune-Win32-Deployer\Win32Apps-DropBox"
        $global:Repo_Path = Convert-WindowsPathToLinuxPath -WindowsPath "C:\Users\Admin-Abdullah\AppData\Local\Intune-Win32-Deployer"
        $global:Repo_winget = "$global:Repo_Path\Win32Apps-DropBox"
    }

    $platform = Get-Platform
    if ($platform -eq 'Win32NT' -or $platform -eq [System.PlatformID]::Win32NT) {
        Setup-WindowsEnvironment
    }
    elseif ($platform -eq 'Unix' -or $platform -eq [System.PlatformID]::Unix) {
        Setup-LinuxEnvironment
    }
    else {
        throw "Unsupported operating system"
    }
}

# Call the function to initialize the environment
Initialize-Environment


# Example usage of global variables outside the function
Write-Output "Global variables set by Initialize-Environment:"
Write-Output "scriptBasePath: $scriptBasePath"
Write-Output "modulesBasePath: $modulesBasePath"
Write-Output "modulePath: $modulePath"
Write-Output "AOscriptDirectory: $AOscriptDirectory"
Write-Output "directoryPath: $directoryPath"
Write-Output "Repo_Path: $Repo_Path"
Write-Output "Repo_winget: $Repo_winget"

#################################################################################################################################
################################################# END VARIABLES #################################################################
#################################################################################################################################

###############################################################################################################################
############################################### START MODULE LOADING ##########################################################
###############################################################################################################################

<#
.SYNOPSIS
Dot-sources all PowerShell scripts in the 'private' folder relative to the script root.

.DESCRIPTION
This function finds all PowerShell (.ps1) scripts in a 'private' folder located in the script root directory and dot-sources them. It logs the process, including any errors encountered, with optional color coding.

.EXAMPLE
Dot-SourcePrivateScripts

Dot-sources all scripts in the 'private' folder and logs the process.

.NOTES
Ensure the Write-EnhancedLog function is defined before using this function for logging purposes.
#>


Write-Host "Starting to call Get-ModulesFolderPath..."

# Store the outcome in $ModulesFolderPath
try {
  
    $ModulesFolderPath = Get-ModulesFolderPath -WindowsPath "C:\code\modules" -UnixPath "/usr/src/code/modules"
    # $ModulesFolderPath = Get-ModulesFolderPath -WindowsPath "$PsScriptRoot\modules" -UnixPath "$PsScriptRoot/modules"
    Write-host "Modules folder path: $ModulesFolderPath"

}
catch {
    Write-Error $_.Exception.Message
}


Write-Host "Starting to call Import-LatestModulesLocalRepository..."
Import-LatestModulesLocalRepository -ModulesFolderPath $ModulesFolderPath

###############################################################################################################################
############################################### END MODULE LOADING ############################################################
###############################################################################################################################
try {
    Ensure-LoggingFunctionExists
    # Continue with the rest of the script here
    # exit
}
catch {
    Write-Host "Critical error: $_" -ForegroundColor Red
    exit
}

###############################################################################################################################
###############################################################################################################################
###############################################################################################################################

# Setup logging
Write-EnhancedLog -Message "Script Started" -Level "INFO"

################################################################################################################################
################################################################################################################################
################################################################################################################################

# Execute InstallAndImportModulesPSGallery function
InstallAndImportModulesPSGallery -moduleJsonPath "$PSScriptRoot/modules.json"

################################################################################################################################
################################################ END MODULE CHECKING ###########################################################
################################################################################################################################

    
################################################################################################################################
################################################ END LOGGING ###################################################################
################################################################################################################################

#  Define the variables to be used for the function
#  $PSADTdownloadParams = @{
#      GithubRepository     = "psappdeploytoolkit/psappdeploytoolkit"
#      FilenamePatternMatch = "PSAppDeployToolkit*.zip"
#      ZipExtractionPath    = Join-Path "$PSScriptRoot\private" "PSAppDeployToolkit"
#  }

#  Call the function with the variables
#  Download-PSAppDeployToolkit @PSADTdownloadParams

################################################################################################################################
################################################ END DOWNLOADING PSADT #########################################################
################################################################################################################################


##########################################################################################################################
############################################STARTING THE MAIN FUNCTION LOGIC HERE#########################################
##########################################################################################################################


################################################################################################################################
################################################ START GRAPH CONNECTING ########################################################
################################################################################################################################
$accessToken = Connect-GraphWithCert -tenantId $tenantId -clientId $clientId -certPath $certPath -certPassword $certPassword

Log-Params -Params @{accessToken = $accessToken }

Get-TenantDetails
#################################################################################################################################
################################################# END Connecting to Graph #######################################################
#################################################################################################################################





# Variables
$endDate = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
$startDate = (Get-Date).AddDays(-30).ToString("yyyy-MM-ddTHH:mm:ssZ")
$baseUrl = "https://graph.microsoft.com/v1.0/auditLogs/signIns"
$headers = @{
    "Authorization" = "Bearer $accessToken"
    "Content-Type"  = "application/json"
}
# Initial URL with filters
$url = "$baseUrl`?`$filter=createdDateTime ge $startDate and createdDateTime le $endDate"
$intuneUrl = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices"
$tenantDetailsUrl = "https://graph.microsoft.com/v1.0/organization"

# Log initial parameters
$params = @{
    AccessToken = $accessToken
    EndDate     = $endDate
    StartDate   = $startDate
    BaseUrl     = $baseUrl
    Url         = $url
    IntuneUrl   = $intuneUrl
    TenantUrl   = $tenantDetailsUrl
}
Log-Params -Params $params

# Function to make the API request and handle pagination


# Validate access to required URIs
$uris = @($url, $intuneUrl, $tenantDetailsUrl)
foreach ($uri in $uris) {
    if (-not (Validate-UriAccess -uri $uri -Headers $headers)) {
        Write-EnhancedLog "Validation failed. Halting script." -Color Red
        exit 1
    }
}


# (we got them already now let's filter them)

# # Get all sign-in logs for the last 30 days
# $signInLogs = Get-SignInLogs -url $url -Headers $headers

# # Export to JSON for further processing
# $signInLogs | ConvertTo-Json -Depth 10 | Out-File -FilePath "/usr/src/SignInLogs.json" -Encoding utf8

# Write-EnhancedLog "Export complete. Check /usr/src/SignInLogs.json for results." -Color Green

# # Load the sign-in logs
# $json = Get-Content -Path '/usr/src/SignInLogs.json' | ConvertFrom-Json




# Define the root path where the scripts and exports are located
# $scriptRoot = "C:\MyScripts"

# Optionally, specify the names for the exports folder and subfolder
$exportsFolderName = "CustomExports"
$exportSubFolderName = "CustomSignInLogs"

# # Call the function to export sign-in logs to XML (and other formats)
# # Define the parameters to be splatted
$ExportAndProcessSignInLogsparams = @{
    ScriptRoot          = $PSscriptRoot
    ExportsFolderName   = $exportsFolderName
    ExportSubFolderName = $exportSubFolderName
    url                 = $url
    Headers             = $headers
}

# Call the function with splatted parameters
# Export-SignInLogs @params


# ExportAndProcessSignInLogs -ScriptRoot $PSscriptRoot -ExportsFolderName $exportsFolderName -ExportSubFolderName $exportSubFolderName -url $url -Headers $headers
ExportAndProcessSignInLogs @ExportAndProcessSignInLogsparams



# # Export to JSON for further processing
# $signInLogs | ConvertTo-Json -Depth 10 | Out-File -FilePath "/usr/src/SignInLogs.json" -Encoding utf8

# Write-EnhancedLog "Export complete. Check /usr/src/SignInLogs.json for results." -Color Green


# Write-EnhancedLog "Export complete. Check ""$PSscriptRoot/$exportsFolderName/$exportSubFolderName/SignInLogs_20240610143318.json"" for results." -Color Green


# # # Load the sign-in logs
# $json = Get-Content -Path "$PSscriptRoot/$exportsFolderName/$exportSubFolderName/SignInLogs_20240610143318.json" | ConvertFrom-Json





# $allSKUs = Get-MgSubscribedSku -Property SkuPartNumber, ServicePlans 
# $allSKUs | ForEach-Object {
#     Write-Host "Service Plan:" $_.SkuPartNumber
#     $_.ServicePlans | ForEach-Object {$_}
# }


# $JSON is being passed from ExportAndProcessSignInLogs.ps1
# $results = Process-AllDevices -Json $Json -Headers $Headers


# Import your module
# Import-Module -Name YourModuleName

# # Check if functions are available
# if (-not (Get-Command Initialize-Results -ErrorAction SilentlyContinue)) {
#     throw "Initialize-Results function not found."
# }
# if (-not (Get-Command Process-DeviceItem -ErrorAction SilentlyContinue)) {
#     throw "Process-DeviceItem function not found."
# }
# if (-not (Get-Command Handle-Error -ErrorAction SilentlyContinue)) {
#     throw "Handle-Error function not found."
# }



write-host 'converting the functions to strings'
$functionInitializeResults = ${function:Initialize-Results}.ToString()
$functionProcessDeviceItem = ${function:Process-DeviceItem}.ToString()
$functionHandleError = ${function:Handle-Error}.ToString()
$functionImportLatestModulesLocalRepository = ${function:Import-LatestModulesLocalRepository}.ToString()
$functionInstallAndImportModulesPSGallery = ${function:InstallAndImportModulesPSGallery}.ToString()

$moduleJsonPath = "$PSScriptRoot/modules.json"

# Call the parallel function
write-host 'Calling parallel function Process-AllDevicesParallel'
$results = Process-AllDevicesParallel -Json $json -Headers $headers `
    -FunctionInitializeResults $functionInitializeResults `
    -FunctionProcessDeviceItem $functionProcessDeviceItem `
    -FunctionHandleError $functionHandleError `
    -FunctionImportLatestModulesLocalRepository $functionImportLatestModulesLocalRepository `
    -FunctionInstallAndImportModulesPSGallery $functionInstallAndImportModulesPSGallery `
    -ModulesFolderPath $ModulesFolderPath `
    -ModuleJsonPath $moduleJsonPath


# $results = Process-AllDevicesParallel -Json $json -Headers $headers


# Output results
# $results | Format-Table -AutoSize




# Output results
# $results | Format-Table -AutoSize #(uncomment to view results)

# $results | Out-GridView -Title 'Corporate VS BYOD Devices - Compliant VS Non-Compliant'






# Export master report
$results | Export-Csv "$PSScriptRoot/$exportsFolderName/MasterReport.csv" -NoTypeInformation


# Exclude PII Removed entries
$filteredResults = $results | Where-Object { $_.DeviceStateInIntune -ne 'External' }

# Generate and export specific reports
$report1 = $filteredResults | Where-Object { ($_.TrustType -eq 'Hybrid Azure AD joined' -or $_.TrustType -eq 'Azure AD Joined') -and $_.DeviceComplianceStatus -eq 'Compliant' }
$report2 = $filteredResults | Where-Object { ($_.TrustType -eq 'Hybrid Azure AD joined' -or $_.TrustType -eq 'Azure AD Joined') -and $_.DeviceComplianceStatus -eq 'Non-Compliant' }
$report3 = $filteredResults | Where-Object { $_.TrustType -eq 'Azure AD Registered' -and $_.DeviceComplianceStatus -eq 'Compliant' }
$report4 = $filteredResults | Where-Object { $_.TrustType -eq 'Azure AD Registered' -and $_.DeviceComplianceStatus -eq 'Non-Compliant' }

$report1 | Export-Csv "$PSScriptRoot/$exportsFolderName/CorporateCompliant.csv" -NoTypeInformation
$report2 | Export-Csv "$PSScriptRoot/$exportsFolderName/CorporateIncompliant.csv" -NoTypeInformation
$report3 | Export-Csv "$PSScriptRoot/$exportsFolderName/BYODCompliant.csv" -NoTypeInformation
$report4 | Export-Csv "$PSScriptRoot/$exportsFolderName/BYOD_AND_CORP_ER_Incompliant.csv" -NoTypeInformation

# Output color-coded stats to console
$totalMaster = $results.Count
$totalReport1 = $report1.Count
$totalReport2 = $report2.Count
$totalReport3 = $report3.Count
$totalReport4 = $report4.Count

Write-EnhancedLog "Total entries in Master Report: $totalMaster" -Color Green
Write-EnhancedLog "Total entries in Corporate Compliant Report: $totalReport1" -Color Cyan
Write-EnhancedLog "Total entries in Corporate Incompliant Report: $totalReport2" -Color Yellow
Write-EnhancedLog "Total entries in BYOD Compliant Report: $totalReport3" -Color Blue
Write-EnhancedLog "Total entries in BYOD and CORP Entra Registered Incompliant Report: $totalReport4" -Color Red




# Group data by compliance status, trust type, device OS, and device state in Intune
$groupedData = $filteredResults | Group-Object -Property DeviceComplianceStatus, TrustType, DeviceOS, DeviceStateInIntune

# Initialize a new List to store the structured data
$structuredData = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($group in $groupedData) {
    $complianceStatus = $group.Name.Split(',')[0].Trim()
    $trustType = $group.Name.Split(',')[1].Trim()
    $deviceOS = $group.Name.Split(',')[2].Trim()
    $deviceStateInIntune = $group.Name.Split(',')[3].Trim()
    $count = $group.Count

    $structuredData.Add([PSCustomObject]@{
            ComplianceStatus    = $complianceStatus
            TrustType           = $trustType
            DeviceOS            = $deviceOS
            DeviceStateInIntune = $deviceStateInIntune
            Count               = $count
        })
}

# Export the structured data to a CSV file
$structuredData | Export-Csv "$PSScriptRoot/$exportsFolderName/StructuredReport.csv" -NoTypeInformation

# Output structured data to console with color coding
foreach ($item in $structuredData) {
    $Level = switch ($item.ComplianceStatus) {
        "Compliant" { "Info" }
        "Non-Compliant" { "Warning" }
        default { "White" }
    }

    $Level = switch ($item.DeviceStateInIntune) {
        "Error" { "Error" }
        "Present" { "Notice" }
        default { "White" }
    }

  

    Write-EnhancedLog -Message "Compliance Status: $($item.ComplianceStatus), Trust Type: $($item.TrustType), Device OS: $($item.DeviceOS), Count: $($item.Count)" -Level $Level
}

# Additional grouping and exporting as needed
$reportCompliant = $structuredData | Where-Object { $_.ComplianceStatus -eq 'Compliant' }
$reportNonCompliant = $structuredData | Where-Object { $_.ComplianceStatus -eq 'Non-Compliant' }
$reportPresent = $structuredData | Where-Object { $_.DeviceStateInIntune -eq 'Present' }
$reportError = $structuredData | Where-Object { $_.DeviceStateInIntune -eq 'Error' }

$reportCompliant | Export-Csv "$PSScriptRoot/$exportsFolderName/Report_Compliant.csv" -NoTypeInformation
$reportNonCompliant | Export-Csv "$PSScriptRoot/$exportsFolderName/Report_NonCompliant.csv" -NoTypeInformation
$reportPresent | Export-Csv "$PSScriptRoot/$exportsFolderName/Report_Present.csv" -NoTypeInformation
$reportError | Export-Csv "$PSScriptRoot/$exportsFolderName/Report_Error.csv" -NoTypeInformation

# Export report for External devices separately
$reportExternal = $results | Where-Object { $_.DeviceStateInIntune -eq 'External' }
$reportExternal | Export-Csv "$PSScriptRoot/$exportsFolderName/Report_External.csv" -NoTypeInformation











Generate-LicenseReports -Results $results -PSScriptRoot $PSScriptRoot -ExportsFolderName $ExportsFolderName
Generate-PII-RemovedReport -Results $results -PSScriptRoot $PSScriptRoot -ExportsFolderName $ExportsFolderName