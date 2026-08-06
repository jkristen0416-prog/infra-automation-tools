#requires -Modules Pester

<#
.SYNOPSIS
    Tests de Get-FreshnessRow (Test-BackupFreshness.ps1) usando mocks.
#>

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\scripts\Test-BackupFreshness.ps1'
    # Dot-source con valor dummy para satisfacer el binding de -Path
    # (obligatorio); el guard interno omite la ejecución del main.
    . $scriptPath -Path 'dummy-path'
}

Describe 'Get-FreshnessRow - carpeta con backup reciente' {
    It 'marca OK cuando el archivo más reciente está dentro del umbral' {
        Mock Test-Path { param($Path, $PathType) return ($PathType -eq 'Container') }
        Mock Get-ChildItem {
            param($LiteralPath, $Filter)
            [PSCustomObject]@{
                Name          = 'backup-2026-08-06.vbk'
                LastWriteTime = (Get-Date).AddHours(-2)
                PSIsContainer = $false
            }
        }

        $row = Get-FreshnessRow -FullPath 'D:\Backups\Veeam' -MaxAgeHours 24 -Now (Get-Date)
        $row.Status | Should -Be 'OK'
        $row.AgeHours | Should -BeLessThan 24
        $row.LatestFile | Should -Be 'backup-2026-08-06.vbk'
    }
}

Describe 'Get-FreshnessRow - carpeta con backup vencido' {
    It 'marca VENCIDO cuando el archivo más reciente supera el umbral' {
        Mock Test-Path { param($Path, $PathType) return ($PathType -eq 'Container') }
        Mock Get-ChildItem {
            param($LiteralPath, $Filter)
            [PSCustomObject]@{
                Name          = 'full-2026-07-30.bak'
                LastWriteTime = (Get-Date).AddHours(-170)
                PSIsContainer = $false
            }
        }

        $row = Get-FreshnessRow -FullPath 'E:\Backups\SQL' -MaxAgeHours 24 -Now (Get-Date)
        $row.Status | Should -Be 'VENCIDO'
        $row.AgeHours | Should -BeGreaterThan 24
    }
}

Describe 'Get-FreshnessRow - archivo individual' {
    It 'evalúa el archivo directamente sin buscar contenido' {
        Mock Test-Path {
            param($Path, $PathType)
            return ($PathType -eq 'Leaf')
        }
        Mock Get-Item {
            [PSCustomObject]@{
                Name          = 'router.rsc'
                LastWriteTime = (Get-Date).AddHours(-3)
            }
        }

        $row = Get-FreshnessRow -FullPath 'D:\Backups\config\router.rsc' -MaxAgeHours 24 -Now (Get-Date)
        $row.Status | Should -Be 'OK'
    }
}

Describe 'Get-FreshnessRow - rutas inexistentes o vacías' {
    It 'marca RUTA INEXISTENTE cuando Test-Path no encuentra nada' {
        Mock Test-Path { return $false }

        $row = Get-FreshnessRow -FullPath 'Z:\NoExiste' -MaxAgeHours 24 -Now (Get-Date)
        $row.Status | Should -Be 'RUTA INEXISTENTE'
    }

    It 'marca SIN ARCHIVOS cuando la carpeta no tiene coincidencias' {
        Mock Test-Path { param($Path, $PathType) return ($PathType -eq 'Container') }
        Mock Get-ChildItem {
            param($LiteralPath, $Filter)
            return @()
        }

        $row = Get-FreshnessRow -FullPath 'D:\Backups\Vacio' -Pattern '*.vbk' -MaxAgeHours 24 -Now (Get-Date)
        $row.Status | Should -Be 'SIN ARCHIVOS'
    }
}
