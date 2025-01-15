# Define error handling preferences
$ErrorActionPreference = 'Stop'


function Write-ConditionalAccessLog {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    
    switch ($Level) {
        'Info' { Write-Host $logMessage -ForegroundColor Green }
        'Warning' { Write-Host $logMessage -ForegroundColor Yellow }
        'Error' { Write-Host $logMessage -ForegroundColor Red }
    }
}


function Test-AdminAndPSVersion {
    Write-ConditionalAccessLog "Checking PowerShell version and administrative privileges..."
    
    $currentPrincipal = [Security.Principal.WindowsPrincipal]::new(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    )
    
    $isAdmin = $currentPrincipal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
    $isPS5 = $PSVersionTable.PSVersion.Major -eq 5

    Write-ConditionalAccessLog "Current PowerShell Version: $($PSVersionTable.PSVersion.ToString())"
    Write-ConditionalAccessLog "Running as Administrator: $isAdmin"

    if (-not $isPS5) {
        Write-ConditionalAccessLog "PowerShell 5 check failed. Current version: $($PSVersionTable.PSVersion.ToString())" -Level Error
        throw [System.InvalidOperationException]::new(
            "PowerShell 5 is required. Current version: $($PSVersionTable.PSVersion.ToString())"
        )
    }
    
    if (-not $isAdmin) {
        Write-ConditionalAccessLog "Administrator privileges check failed" -Level Error
        throw [System.UnauthorizedAccessException]::new(
            'Administrator rights are required to run this script.'
        )
    }

    Write-ConditionalAccessLog "All prerequisite checks passed successfully"
    return $true
}

function Install-RequiredModule {
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName
    )

    Write-ConditionalAccessLog "Checking module: $ModuleName"
    Test-AdminAndPSVersion | Out-Null

    if (Get-Module -ListAvailable -Name $ModuleName) {
        Write-ConditionalAccessLog "Module '$ModuleName' is already installed"
        $existingVersion = (Get-Module -ListAvailable -Name $ModuleName | Sort-Object Version -Descending | Select-Object -First 1).Version
        Write-ConditionalAccessLog "Current version: $existingVersion"
    }
    else {
        Write-ConditionalAccessLog "Module '$ModuleName' not found. Attempting installation..."
        $installParams = @{
            Name         = $ModuleName
            Force        = $true
            AllowClobber = $true
            Scope        = 'AllUsers'
            ErrorAction  = 'Stop'
        }
        
        try {
            Install-Module @installParams
            $installedVersion = (Get-Module -ListAvailable -Name $ModuleName | Sort-Object Version -Descending | Select-Object -First 1).Version
            Write-ConditionalAccessLog "Successfully installed '$ModuleName' version $installedVersion"
        }
        catch {
            Write-ConditionalAccessLog "Failed to install module '$ModuleName': $_" -Level Error
            throw [System.Management.Automation.ItemNotFoundException]::new(
                "Failed to install module '$ModuleName': $_"
            )
        }
    }
}

# Required modules
$requiredModules = @(
    'Microsoft.Graph.Users'
    'Microsoft.Graph.Identity.DirectoryManagement'
    'Microsoft.Graph.Authentication'
    'ExchangeOnlineManagement'
    'Microsoft.Graph.Beta.Identity.SignIns'
    'Microsoft.Graph.Groups',
    'Microsoft.Graph.Identity.SignIns',
    'Microsoft.Graph.Beta.Identity.DirectoryManagement'
    
)

# Main execution block
try {
    Write-ConditionalAccessLog "=== Starting Module Installation Process ==="
    Write-ConditionalAccessLog "Required modules: $($requiredModules -join ', ')"
    
    foreach ($module in $requiredModules) {
        Install-RequiredModule -ModuleName $module
    }
    
    Write-ConditionalAccessLog "Importing all required modules..."
    Import-Module -Name $requiredModules -ErrorAction Stop
    Write-ConditionalAccessLog "=== Module Installation Process Completed Successfully ==="
}
catch {
    Write-ConditionalAccessLog "=== Module Installation Process Failed ===" -Level Error
    throw "Module installation failed: $_"
}


function Import-RequiredModules {
    [CmdletBinding()]
    param()
    
    $logParams = @{
        Message = "Importing required Microsoft Graph modules"
        Level   = "Info"
    }
    Write-ConditionalAccessLog @logParams

    try {
        # Remove existing modules first to avoid assembly conflicts
        $modulesToRemove = @(
            'Microsoft.Graph.Users'
            'Microsoft.Graph.Groups'
            'Microsoft.Graph.Authentication'
            'Microsoft.Graph.Beta.Identity.SignIns'
        )

        foreach ($module in $modulesToRemove) {
            if (Get-Module $module) {
                $removeParams = @{
                    Name        = $module
                    Force       = $true
                    ErrorAction = "SilentlyContinue"
                }
                Remove-Module @removeParams
            }
        }

        # Import required modules
        $modulesToImport = @(
            'Microsoft.Graph.Users'
            'Microsoft.Graph.Identity.DirectoryManagement'
            'Microsoft.Graph.Authentication'
            'ExchangeOnlineManagement'
            'Microsoft.Graph.Beta.Identity.SignIns'
            'Microsoft.Graph.Groups',
            'Microsoft.Graph.Identity.SignIns',
            'Microsoft.Graph.Beta.Identity.DirectoryManagement'
        )

        foreach ($module in $modulesToImport) {
            $importParams = @{
                Name        = $module
                Force       = $true
                ErrorAction = "Stop"
            }
            Import-Module @importParams
            
            $logParams = @{
                Message = "Successfully imported module: $module"
                Level   = "Info"
            }
            Write-ConditionalAccessLog @logParams
        }

        return $true
    }
    catch {
        $logParams = @{
            Message = "Failed to import required modules: $_"
            Level   = "Error"
        }
        Write-ConditionalAccessLog @logParams
        throw
    }
}


Import-RequiredModules




# Enhanced Connection Functions for Graph and Exchange Online

function Connect-GraphWithScope {
    [CmdletBinding()]
    param()
    
    # Define the scopes in an array
    $requiredScopes = @(
        "RoleAssignmentSchedule.ReadWrite.Directory",
        "Domain.Read.All",
        "Domain.ReadWrite.All",
        "Directory.Read.All",
        "Policy.ReadWrite.ConditionalAccess",
        "DeviceManagementApps.ReadWrite.All",
        "DeviceManagementConfiguration.ReadWrite.All",
        "DeviceManagementManagedDevices.ReadWrite.All",
        "openid",
        "profile",
        "email",
        "offline_access",
        "Policy.ReadWrite.PermissionGrant",
        "RoleManagement.ReadWrite.Directory",
        "Policy.ReadWrite.DeviceConfiguration",
        "DeviceLocalCredential.Read.All",
        "DeviceManagementManagedDevices.PrivilegedOperations.All",
        "DeviceManagementServiceConfig.ReadWrite.All",
        "Policy.Read.All",
        "DeviceManagementRBAC.ReadWrite.All",
        "UserAuthenticationMethod.ReadWrite.All",
        "User.Read.All",
        "Group.ReadWrite.All",
        "Directory.ReadWrite.All",
        "User.ReadWrite.All",
        "Application.Read.All"
    )
    
    Write-ConditionalAccessLog "Checking Microsoft Graph connection..."
    $currentContext = Get-MgContext
    
    if ($null -eq $currentContext) {
        Write-ConditionalAccessLog "No existing Graph connection found. Connecting..." -Level Warning
        Connect-MgGraph -Scopes $requiredScopes
        $newContext = Get-MgContext
        Write-ConditionalAccessLog "Connected to Microsoft Graph as: $($newContext.Account)" -Level Info
        return
    }
    
    $missingScopes = $requiredScopes | Where-Object { $_ -notin $currentContext.Scopes }
    
    if ($missingScopes) {
        Write-ConditionalAccessLog "Missing required scopes: $($missingScopes -join ', ')" -Level Warning
        Write-ConditionalAccessLog "Reconnecting with all required scopes..." -Level Warning
        Disconnect-MgGraph
        Connect-MgGraph -Scopes $requiredScopes
        $newContext = Get-MgContext
        Write-ConditionalAccessLog "Reconnected to Microsoft Graph as: $($newContext.Account)" -Level Info
    }
    else {
        Write-ConditionalAccessLog "Already connected to Microsoft Graph with required scopes as: $($currentContext.Account)" -Level Info
    }
}

function Connect-RequiredServices {
    [CmdletBinding()]
    param()
    
    Write-ConditionalAccessLog "=== Starting Service Connections ===" -Level Info
    
    try {
        Connect-GraphWithScope
        Write-ConditionalAccessLog "=== All Service Connections Completed Successfully ===" -Level Info
    }
    catch {
        Write-ConditionalAccessLog "=== Service Connection Process Failed ===" -Level Error
        throw "Failed to connect to required services: $_"
    }
}



Connect-RequiredServices