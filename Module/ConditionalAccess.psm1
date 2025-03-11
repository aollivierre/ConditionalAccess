# Import all public functions
Get-ChildItem -Path $PSScriptRoot\Public\*.ps1 -ErrorAction SilentlyContinue | 
    ForEach-Object { . $_.FullName }

# Import all private functions
Get-ChildItem -Path $PSScriptRoot\Private\*.ps1 -ErrorAction SilentlyContinue | 
    ForEach-Object { . $_.FullName }

# Export public functions
Export-ModuleMember -Function (Get-ChildItem -Path $PSScriptRoot\Public\*.ps1).BaseName
