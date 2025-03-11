function Get-GuestUserTypes {
    [CmdletBinding()]
    param()
    
    @(
        [PSCustomObject]@{
            DisplayName = "Internal guest users"
            Id = "internalGuest"
            Description = "Guest users within your organization"
            Category = "Internal"
        },
        [PSCustomObject]@{
            DisplayName = "B2B collaboration guest users"
            Id = "b2bCollaborationGuest"
            Description = "Users invited to collaborate with your organization"
            Category = "B2B"
        },
        [PSCustomObject]@{
            DisplayName = "B2B collaboration member users"
            Id = "b2bCollaborationMember"
            Description = "Members from other organizations"
            Category = "B2B"
        },
        [PSCustomObject]@{
            DisplayName = "B2B direct connect users"
            Id = "b2bDirectConnectUser"
            Description = "Users connecting directly from partner organizations"
            Category = "B2B"
        },
        [PSCustomObject]@{
            DisplayName = "Other external users"
            Id = "otherExternalUser"
            Description = "All other types of external users"
            Category = "External"
        },
        [PSCustomObject]@{
            DisplayName = "Service provider users"
            Id = "serviceProvider"
            Description = "Users from service provider organizations"
            Category = "External"
        }
    ) | Sort-Object Category, DisplayName
}