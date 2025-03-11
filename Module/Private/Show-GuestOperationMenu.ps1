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
