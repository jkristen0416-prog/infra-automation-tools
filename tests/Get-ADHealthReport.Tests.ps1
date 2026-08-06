#requires -Modules Pester

<#
.SYNOPSIS
    Tests de Get-DomainMaxPasswordAge y Get-PasswordExpiringUser
    (Get-ADHealthReport.ps1) usando mocks.
#>

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\scripts\Get-ADHealthReport.ps1'
    # Stubs para cmdlets del módulo ActiveDirectory (no instalado en el runner):
    # permiten que Pester registre mocks sobre ellos.
    function Get-ADDefaultDomainPasswordPolicy { throw 'stub - debe ser mockeado' }
    . $scriptPath  # dot-source: carga funciones sin ejecutar el main
}

Describe 'Get-DomainMaxPasswordAge' {
    It 'usa Get-ADDefaultDomainPasswordPolicy (vía oficial) cuando está disponible' {
        Mock Get-ADDefaultDomainPasswordPolicy {
            [PSCustomObject]@{ MaxPasswordAge = [TimeSpan]::FromDays(60) }
        }

        $days = Get-DomainMaxPasswordAge -SessionParams @{}
        $days | Should -Be 60
        Should -Invoke Get-ADDefaultDomainPasswordPolicy -Times 1 -Exactly
    }

    It 'hace fallback a Get-ADDomain cuando la política predeterminada no existe' {
        Mock Get-ADDefaultDomainPasswordPolicy { throw 'No se pudo consultar' }
        $domainInfo = [PSCustomObject]@{ MaxPasswordAge = [TimeSpan]::FromDays(90) }

        $days = Get-DomainMaxPasswordAge -SessionParams @{} -DomainInfo $domainInfo
        $days | Should -Be 90
    }

    It 'devuelve $null cuando no hay política consultable' {
        Mock Get-ADDefaultDomainPasswordPolicy { throw 'No se pudo consultar' }

        $days = Get-DomainMaxPasswordAge -SessionParams @{} -DomainInfo $null
        $days | Should -BeNullOrEmpty
    }
}

Describe 'Get-PasswordExpiringUser' {
    BeforeAll {
        $now = Get-Date
        $users = @(
            [PSCustomObject]@{ Name = 'user-ok';       PasswordLastSet = $now.AddDays(-30); PasswordNeverExpires = $false; Enabled = $true }
            [PSCustomObject]@{ Name = 'user-expiring'; PasswordLastSet = $now.AddDays(-50); PasswordNeverExpires = $false; Enabled = $true }
            [PSCustomObject]@{ Name = 'user-never';    PasswordLastSet = $now.AddDays(-50); PasswordNeverExpires = $true;  Enabled = $true }
            [PSCustomObject]@{ Name = 'user-disabled'; PasswordLastSet = $now.AddDays(-50); PasswordNeverExpires = $false; Enabled = $false }
            [PSCustomObject]@{ Name = 'user-nopwd';    PasswordLastSet = $null;             PasswordNeverExpires = $false; Enabled = $true }
        )
    }

    It 'detecta solo usuarios habilitados con contraseña que vence pronto' {
        # maxPwdAge 60 días, umbral 14: expiran a los 46+ días de antigüedad
        $expiring = Get-PasswordExpiringUser -Users $users -MaxAgeDays 60 -ExpiryWarningDays 14 -Now $now
        $expiring.Name | Should -Be @('user-expiring')
    }

    It 'devuelve lista vacía cuando no hay MaxAgeDays' {
        $expiring = Get-PasswordExpiringUser -Users $users -MaxAgeDays 0 -ExpiryWarningDays 14 -Now $now
        $expiring | Should -HaveCount 0
    }

    It 'respeta el umbral de advertencia configurable' {
        # umbral 1 día: solo expira lo que está a menos de 1 día de vencer
        $expiring = Get-PasswordExpiringUser -Users $users -MaxAgeDays 60 -ExpiryWarningDays 1 -Now $now
        $expiring | Should -HaveCount 0
    }
}
