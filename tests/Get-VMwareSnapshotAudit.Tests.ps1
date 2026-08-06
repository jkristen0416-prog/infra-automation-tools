#requires -Modules Pester

<#
.SYNOPSIS
    Tests de Get-SnapshotAuditRow y Format-Size (Get-VMwareSnapshotAudit.ps1)
    usando mocks.
#>

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\scripts\Get-VMwareSnapshotAudit.ps1'
    # Dot-source con valor dummy para satisfacer el binding de -VCenter
    # (obligatorio); el guard interno omite la ejecución del main.
    . $scriptPath -VCenter 'dummy-vcenter'
}

Describe 'Get-SnapshotAuditRow' {
    BeforeAll {
        $now = Get-Date
        $snapOld = [PSCustomObject]@{
            Name        = 'pre-upgrade'
            Description = 'Snapshot antes de upgrade'
            Created     = $now.AddDays(-45)
            SizeGB      = 12.5
            IsCurrent   = $false
        }
        $snapNew = [PSCustomObject]@{
            Name        = 'baseline'
            Description = 'Baseline'
            Created     = $now.AddDays(-5)
            SizeGB      = 3.1
            IsCurrent   = $true
        }
    }

    It 'marca STALE cuando el snapshot supera el umbral de antigüedad' {
        $row = Get-SnapshotAuditRow -VMName 'web-prod-01' -Snapshot $snapOld -MaxAgeDays 30 -Now $now
        $row.Status | Should -Be 'STALE'
        $row.AgeDays | Should -BeGreaterThan 30
        $row.VMName | Should -Be 'web-prod-01'
    }

    It 'marca OK cuando el snapshot está dentro del umbral' {
        $row = Get-SnapshotAuditRow -VMName 'app-dev-03' -Snapshot $snapNew -MaxAgeDays 30 -Now $now
        $row.Status | Should -Be 'OK'
        $row.IsCurrent | Should -Be $true
    }

    It 'devuelve el tamaño formateado en GB' {
        $row = Get-SnapshotAuditRow -VMName 'sql-prod-02' -Snapshot $snapOld -MaxAgeDays 30 -Now $now
        $row.Size | Should -Match '^12\.50 GB$'
    }
}

Describe 'Format-Size' {
    It 'formatea gigabytes correctamente (bug de unidades regresión)' {
        Format-Size 12.5   | Should -Be '12.50 GB'
        Format-Size 0.9    | Should -Be '0.90 GB'
        Format-Size 1024.5 | Should -Be '1,024.50 GB'
    }
}
