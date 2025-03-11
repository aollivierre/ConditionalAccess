
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
        
        # Get operation type
        $operation = Show-GuestOperationMenu
        if ($operation -eq 'Cancel') {
            Write-Host "`nOperation cancelled by user." -ForegroundColor Yellow
            return
        }
        
        Write-Host "`nSelected Operation: $operation" -ForegroundColor Green
        
        # Get current policies
        Write-Host "`nRetrieving current policy information..." -ForegroundColor Cyan
        $policies = Get-ConditionalAccessPoliciesDetails
        
        if (-not $policies) {
            Write-Warning "No policies found to process."
            return
        }
        
        # Select policies to update
        Write-Host "`nSelect policies to update..." -ForegroundColor Cyan
        $selectedPolicies = $policies | 
            Out-GridView -Title "Select Conditional Access Policies to Modify" -PassThru
        
        if (-not $selectedPolicies) {
            Write-Warning "No policies selected for processing."
            return
        }

        # Select guest types
        Write-Host "`nSelect guest types to $($operation.ToLower())..." -ForegroundColor Cyan
        $guestTypes = Get-GuestUserTypes
        
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
        $selectedGuestTypes | ForEach-Object { Write-Host "- $($_.DisplayName)" -ForegroundColor Gray }
        
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
                    GuestTypesUpdated = $selectedGuestTypes.DisplayName -join ', '
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