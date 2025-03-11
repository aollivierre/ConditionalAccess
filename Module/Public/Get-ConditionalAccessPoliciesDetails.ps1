function Get-ConditionalAccessPoliciesDetails {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet('All', 'Guest', 'AdminRoles')]
        [string]$PolicyType = 'All'
    )
    
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
            } else {
                1.0
            }
            
            # Build the admin roles status
            $adminRolesStatus = [System.Collections.ArrayList]::new()
            if ($PolicyType -in @('All', 'AdminRoles')) {
                if ($policy.Conditions.Users.IncludeRoles.Count -gt 0) {
                    $null = $adminRolesStatus.Add("Include: $($policy.Conditions.Users.IncludeRoles.Count) roles")
                }
                
                if ($policy.Conditions.Users.ExcludeRoles.Count -gt 0) {
                    $null = $adminRolesStatus.Add("Exclude: $($policy.Conditions.Users.ExcludeRoles.Count) roles")
                }
            }
            
            # Build the guest status
            $guestStatus = [System.Collections.ArrayList]::new()
            if ($PolicyType -in @('All', 'Guest')) {
                if ($policy.Conditions.Users.IncludeGuestsOrExternalUsers) {
                    $null = $guestStatus.Add("Include: Guest/External Users")
                }
                
                if ($policy.Conditions.Users.ExcludeGuestsOrExternalUsers) {
                    $null = $guestStatus.Add("Exclude: Guest/External Users")
                }
            }
            
            # Format status strings
            $currentAdminRoles = if ($adminRolesStatus.Count -gt 0) {
                $adminRolesStatus -join ' | '
            } else {
                "No admin roles configured"
            }
            
            $currentGuestStatus = if ($guestStatus.Count -gt 0) {
                $guestStatus -join ' | '
            } else {
                "No guest configuration"
            }
            
            # Create output object based on PolicyType
            $outputObject = [ordered]@{
                DisplayName = $policy.DisplayName
                Id         = $policy.Id
                State      = $policy.State
                Version    = $version
            }

            # Add type-specific properties based on PolicyType
            switch ($PolicyType) {
                'All' {
                    $outputObject['CurrentAdminRoles'] = $currentAdminRoles
                    $outputObject['CurrentGuestStatus'] = $currentGuestStatus
                }
                'Guest' {
                    $outputObject['CurrentGuestStatus'] = $currentGuestStatus
                }
                'AdminRoles' {
                    $outputObject['CurrentAdminRoles'] = $currentAdminRoles
                }
            }

            [PSCustomObject]$outputObject
        })

        Write-Verbose "Returning $($formattedPolicies.Count) formatted policies"
        return $formattedPolicies
    }
    catch {
        Write-Error "Failed to retrieve or process Conditional Access Policies: $_"
        return @()
    }
}



# # Get all policy details
# Get-ConditionalAccessPoliciesDetails -PolicyType All

# # Get only guest-related details
# Get-ConditionalAccessPoliciesDetails -PolicyType Guest

# # Get only admin role details
# Get-ConditionalAccessPoliciesDetails -PolicyType AdminRoles

# # With verbose output
# Get-ConditionalAccessPoliciesDetails -PolicyType All -Verbose