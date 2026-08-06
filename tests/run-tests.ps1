# Runner de tests local (Pester 5+)
Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop
$config = New-PesterConfiguration
$config.Run.Path = $PSScriptRoot
$config.Output.Verbosity = 'Detailed'
$config.Run.Exit = $true
Invoke-Pester -Configuration $config
