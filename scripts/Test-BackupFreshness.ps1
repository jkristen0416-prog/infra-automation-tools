<#
.SYNOPSIS
    Verifica que los archivos/carpetas de backup más recientes no superen un
    umbral de antigüedad configurado.

.DESCRIPTION
    Escanea un conjunto de rutas (carpetas o archivos individuales) y calcula
    la antigüedad del elemento más reciente dentro de cada una. Si un backup
    supera la antigüedad máxima permitida, se marca como VENCIDO.

    Pensado para integrarse con sistemas de monitoreo (Zabbix, Nagios, tareas
    programadas): devuelve exit code 0 si todo está al día, 1 si hay backups
    vencidos y 2 si ocurrió un error de ejecución.

.PARAMETER Path
    Ruta o rutas a verificar (array). Pueden ser carpetas (se toma el archivo
    más reciente del contenido) o archivos individuales. Obligatorio.

.PARAMETER MaxAgeHours
    Antigüedad máxima permitida en horas para un backup.
    Valor por defecto: 24.

.PARAMETER Pattern
    Patrón de filtro de archivos dentro de las carpetas (ej: *.bak, *.vbk).
    Por defecto se consideran todos los archivos.

.PARAMETER ExportPath
    Ruta del archivo de exportación (.csv o .json). Opcional.

.PARAMETER ExitOnStale
    Devuelve exit code 1 cuando existe al menos un backup vencido.
    Sin este parámetro, el script siempre termina con 0 (salvo errores).

.EXAMPLE
    # Verifica una carpeta de backups de Veeam (máximo 24h de antigüedad)
    .\Test-BackupFreshness.ps1 -Path "D:\Backups\Veeam" -MaxAgeHours 24

.EXAMPLE
    # Verifica varias rutas con patrón específico y alerta por exit code
    .\Test-BackupFreshness.ps1 -Path "D:\Backups\Veeam","E:\Backups\SQL" -Pattern "*.vbk" -MaxAgeHours 36 -ExitOnStale

.EXAMPLE
    # Exporta el reporte en JSON para integrarlo a un dashboard
    .\Test-BackupFreshness.ps1 -Path "\\nas01\backups" -MaxAgeHours 48 -ExportPath "C:\Reports\backup-freshness.json"

.NOTES
    Requisitos:
    - Permisos de lectura sobre las rutas verificadas.
    - En rutas UNC, ejecutar con una cuenta con acceso a la red (o credenciales
      establecidas con New-SmbMapping).

    Seguridad:
    - No almacenar credenciales en el script; usar sesión con permisos.
    - Los reportes pueden revelar nombres de rutas internas; protegerlos.

    Autor: jkristen
    Versión: 1.0.0
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [string[]]$Path,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 8760)]
    [int]$MaxAgeHours = 24,

    [Parameter(Mandatory = $false)]
    [string]$Pattern = '*',

    [Parameter(Mandatory = $false)]
    [string]$ExportPath,

    [Parameter(Mandatory = $false)]
    [switch]$ExitOnStale
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Funciones (testables vía dot-source + Pester mocks)
# ---------------------------------------------------------------------------

function Get-FreshnessRow {
    <#
    .SYNOPSIS
        Evalúa una ruta de backup y devuelve la fila de estado.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FullPath,

        [Parameter(Mandatory = $false)]
        [string]$Pattern = '*',

        [Parameter(Mandatory = $false)]
        [int]$MaxAgeHours = 24,

        [Parameter(Mandatory = $false)]
        [datetime]$Now = (Get-Date)
    )

    if (Test-Path -LiteralPath $FullPath -PathType Container) {
        # Es una carpeta: buscar el archivo más reciente que cumpla el patrón
        # Nota: se filtra por PSIsContainer en lugar de -File para que la
        # firma sea compatible con mocks de Pester (los parámetros dinámicos
        # del provider no se heredan en los mocks).
        $latest = Get-ChildItem -LiteralPath $FullPath -Filter $Pattern -ErrorAction SilentlyContinue |
            Where-Object { -not $_.PSIsContainer } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1

        if (-not $latest) {
            Write-Warning "Sin archivos que coincidan con '$Pattern' en: $FullPath"
            return [PSCustomObject]@{
                Path        = $FullPath
                LatestFile  = ''
                LastWrite   = ''
                AgeHours    = $null
                MaxAgeHours = $MaxAgeHours
                Status      = 'SIN ARCHIVOS'
            }
        }
    }
    elseif (Test-Path -LiteralPath $FullPath -PathType Leaf) {
        # Es un archivo individual
        $latest = Get-Item -LiteralPath $FullPath
    }
    else {
        Write-Warning "Ruta no encontrada: $FullPath"
        return [PSCustomObject]@{
            Path        = $FullPath
            LatestFile  = ''
            LastWrite   = ''
            AgeHours    = $null
            MaxAgeHours = $MaxAgeHours
            Status      = 'RUTA INEXISTENTE'
        }
    }

    $ageHours = [math]::Round(($Now - $latest.LastWriteTime).TotalHours, 1)
    $isStale = $ageHours -gt $MaxAgeHours

    return [PSCustomObject]@{
        Path        = $FullPath
        LatestFile  = $latest.Name
        LastWrite   = $latest.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
        AgeHours    = $ageHours
        MaxAgeHours = $MaxAgeHours
        Status      = if ($isStale) { 'VENCIDO' } else { 'OK' }
    }
}

# ---------------------------------------------------------------------------
# Main (se omite al dot-sourcear para permitir pruebas con Pester)
# ---------------------------------------------------------------------------

if ($MyInvocation.InvocationName -ne '.') {
    try {
        $now = Get-Date
        $rows = @()
        $staleCount = 0
        $errorCount = 0

        foreach ($item in $Path) {
            $fullPath = [System.IO.Path]::GetFullPath($item)

            Write-Verbose "Procesando: $fullPath"

            $row = Get-FreshnessRow -FullPath $fullPath -Pattern $Pattern -MaxAgeHours $MaxAgeHours -Now $now

            if ($row.Status -eq 'VENCIDO') { $staleCount++ }
            if ($row.Status -in @('SIN ARCHIVOS', 'RUTA INEXISTENTE')) { $errorCount++ }

            $rows += $row
        }

        # Salida por consola
        $rows | Format-Table Path, LatestFile, LastWrite, AgeHours, Status -AutoSize

        if ($staleCount -gt 0) {
            Write-Host "`nALERTA: $staleCount backup(s) vencido(s) (mayores a $MaxAgeHours horas)." -ForegroundColor Yellow
        }
        if ($errorCount -gt 0) {
            Write-Host "ATENCION: $errorCount ruta(s) con problemas de acceso o sin archivos." -ForegroundColor Yellow
        }

        if ($ExportPath) {
            $ext = [System.IO.Path]::GetExtension($ExportPath).ToLowerInvariant()
            switch ($ext) {
                '.json' {
                    $rows | ConvertTo-Json -Depth 3 | Set-Content -Path $ExportPath -Encoding UTF8
                }
                '.csv'  {
                    $rows | ConvertTo-Csv -NoTypeInformation | Set-Content -Path $ExportPath -Encoding UTF8
                }
                default { throw "Formato no soportado: $ext. Use .csv o .json." }
            }
            Write-Host "Reporte exportado a: $ExportPath" -ForegroundColor Green
        }

        # Exit code para monitoreo
        if ($ExitOnStale -and $staleCount -gt 0) { exit 1 }
        if ($errorCount -gt 0 -and -not $ExitOnStale) { exit 0 }
        if ($errorCount -gt 0) { exit 1 }
        exit 0
    }
    catch {
        Write-Error "Test-BackupFreshness falló: $($_.Exception.Message)"
        exit 2
    }
}
