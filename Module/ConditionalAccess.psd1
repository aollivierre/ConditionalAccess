@{
    ModuleVersion = '1.0.0'
    GUID = New-Guid
    Author = 'Your Name'
    CompanyName = 'Your Company'
    Copyright = '(c) 2025. All rights reserved.'
    Description = 'Module for managing Conditional Access Policies with focus on Guest Access'
    PowerShellVersion = '5.1'
    RequiredModules = @(
        'Microsoft.Graph.Identity.SignIns',
        'PSWriteHTML'
    )
    FunctionsToExport = @(
        'Get-ConditionalAccessPoliciesDetails',
        'Export-GuestPolicyReport',
        'Update-ConditionalAccessPolicyGuestTypes'
    )
    PrivateData = @{
        PSData = @{
            Tags = @('ConditionalAccess', 'Azure', 'Security', 'Guest')
            ProjectUri = ''
        }
    }
}
