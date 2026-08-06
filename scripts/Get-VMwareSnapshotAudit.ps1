<#
.SYNOPSIS
    Audita los snapshots de una plataforma VMware vCenter y reporta los que
    superan una antigüedad configurable.

.DESCRIPTION
    Se conecta a un vCenter Server, enumera todas las máquinas virtuales con
    snapshots y genera un reporte con: nombre de VM, nombre del snapshot,
    fecha de creación, antigüedad en días, tamaño y descripción.

    Los snapshots más antiguos que el umbral configurado se marcan como
    "STALE" para facilitar su revisión. El resultado puede exportarse a CSV
    o JSON y puede generar un exit code distinto de cero cuando existen
    snapshots vencidos (útil para monitoreo o tareas programadas).

.PARAMETER VCenter
    Nombre FQDN o dirección IP del vCenter Server a consultar.
    Obligatorio.

.PARAMETER Credential
    Credencial con permisos de solo lectura sobre el vCenter.
    Si se omite, se solicita interactivamente.

.PARAMETER MaxAgeDays
    Antigüedad máxima aceptable de un snapshot, en días.
    Valor por defecto: 30.

.PARAMETER ExportPath
    Ruta del archivo de exportación (.csv o .json). Opcional.

.PARAMETER ExitOnStale
    Devuelve exit code 1 si existe al menos un snapshot vencido (STALE).

.PARAMETER SkipCertificateCheck
    Omite la validación del certificado TLS del vCenter (solo entornos de
    laboratorio o con certificados autofirmados conocidos).

.EXAMPLE
    # Auditoría básica contra el vCenter del entorno de producción
    .\Get-VMwareSnapshotAudit.ps1 -VCenter vc01.corp.local

.EXAMPLE
    # Auditoría con umbral de 7 días, exportación JSON y alerta por exit code
    .\Get-VMwareSnapshotAudit.ps1 -VCenter vc01.corp.local -MaxAgeDays 7 -ExportPath "D:\Audit\snapshots.json" -ExitOnStale

.EXAMPLE
    # Entorno de laboratorio con certificado autofirmado
    .\Get-VMwareSnapshotAudit.ps1 -VCenter 192.168.10.50 -SkipCertificateCheck

.NOTES
    Requisitos:
    - VMware PowerCLI (Install-Module VMware.PowerCLI).
    - Cuenta con permiso de solo lectura sobre VMs y snapshots.

    Seguridad:
    - Usar cuentas con el mínimo privilegio necesario (lectura).
    - No exponer credenciales en el script; usar -Credential o Get-Credential.
    - Los snapshots antiguos consumen espacio y pueden afectar el rendimiento;
      este script solo audita, no elimina.

    Autor: jkristen
    Versión: 1.0.0
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$VCenter,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.PSCredential]$Credential,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 3650)]
    [int]$MaxAgeDays = 30,

    [Parameter(Mandatory = $false)]
    [string]$ExportPath,

    [Parameter(Mandatory = $false)]
    [switch]$ExitOnStale,

    [Parameter(Mandatory = $false)]
    [switch]$SkipCertificateCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Assert-PowerCLI {
    if (-not (Get-Module -Name VMware.PowerCLI -ListAvailable)) {
        throw "VMware PowerCLI no está instalado. Ejecute: Install-Module VMware.PowerCLI -Scope CurrentUser"
    }
    Import-Module -Name VMware.PowerCLI -ErrorAction Stop
}

function Initialize-CertificatePolicy {
    param(
        [switch]$SkipValidation
    )
    if ($SkipValidation) {
        Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
        Write-Warning "Validación de certificado TLS deshabilitada (-SkipCertificateCheck). Solo para laboratorio."
    }
    else {
        Set-PowerCLIConfiguration -InvalidCertificateAction Fail -Confirm:$false | Out-Null
    }
}

function Format-Size {
    param([double]$SizeGb)
    return ('{0:N2} GB' -f $SizeGb)
}

function Get-SnapshotAuditRow {
    <#
    .SYNOPSIS
        Genera la fila de auditoría a partir de un snapshot de vSphere.
        Devuelve un PSCustomObject con estado OK o STALE según el umbral.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMName,

        [Parameter(Mandatory = $true)]
        [object]$Snapshot,

        [Parameter(Mandatory = $false)]
        [int]$MaxAgeDays = 30,

        [Parameter(Mandatory = $false)]
        [datetime]$Now = (Get-Date)
    )

    $ageDays = [math]::Round(($Now - $Snapshot.Created).TotalDays, 1)
    $isStale = $ageDays -gt $MaxAgeDays

    return [PSCustomObject]@{
        VMName        = $VMName
        SnapshotName  = $Snapshot.Name
        Description   = $Snapshot.Description
        Created       = $Snapshot.Created.ToString('yyyy-MM-dd HH:mm:ss')
        AgeDays       = $ageDays
        Size          = Format-Size ([double]$Snapshot.SizeGB)
        IsCurrent     = $Snapshot.IsCurrent
        Status        = if ($isStale) { 'STALE' } else { 'OK' }
    }
}

# ---------------------------------------------------------------------------
# Main (se omite al dot-sourcear para permitir pruebas con Pester)
# ---------------------------------------------------------------------------

if ($MyInvocation.InvocationName -ne '.') {
    try {
        Assert-PowerCLI
        Initialize-CertificatePolicy -SkipValidation:$SkipCertificateCheck

        Write-Verbose "Conectando a vCenter: $VCenter"
        $cred = $Credential
        if (-not $cred) {
            $cred = Get-Credential -Message "Credenciales para $VCenter"
        }

        $connectArgs = @{
            Server        = $VCenter
            Credential    = $cred
            ErrorAction   = 'Stop'
        }
        $viServer = Connect-VIServer @connectArgs

        Write-Verbose "Enumerando VMs con snapshots..."
        $vms = Get-VM | Where-Object { $_.ExtensionData.Snapshot }

        $now = Get-Date
        $staleCount = 0
        $rows = @()

        foreach ($vm in $vms) {
            $snapshots = Get-Snapshot -VM $vm | Sort-Object Created

            foreach ($snap in $snapshots) {
                $row = Get-SnapshotAuditRow -VMName $vm.Name -Snapshot $snap -MaxAgeDays $MaxAgeDays -Now $now
                if ($row.Status -eq 'STALE') { $staleCount++ }
                $rows += $row
            }
        }

    $summary = [PSCustomObject]@{
        GeneratedAt      = $now.ToString('yyyy-MM-dd HH:mm:ss')
        VCenter          = $VCenter
        VMsWithSnapshots = @($vms).Count
        TotalSnapshots   = @($rows).Count
        StaleSnapshots   = $staleCount
        MaxAgeDays       = $MaxAgeDays
        StaleThreshold   = "$MaxAgeDays dias"
    }

    $summary | Format-List | Out-String | Write-Output

    if ($rows.Count -gt 0) {
        $rows | Sort-Object AgeDays -Descending | Format-Table VMName, SnapshotName, AgeDays, Size, Status -AutoSize
    }
    else {
        Write-Host "No se encontraron snapshots en la plataforma." -ForegroundColor Green
    }

    if ($staleCount -gt 0) {
        Write-Host "`nALERTA: $staleCount snapshot(s) superan los $MaxAgeDays dias. Revisar y consolidar." -ForegroundColor Yellow
    }

    if ($ExportPath) {
        $ext = [System.IO.Path]::GetExtension($ExportPath).ToLowerInvariant()
        switch ($ext) {
            '.json' {
                @{ Summary = $summary; Snapshots = $rows } | ConvertTo-Json -Depth 4 |
                    Set-Content -Path $ExportPath -Encoding UTF8
            }
            '.csv'  { $rows | ConvertTo-Csv -NoTypeInformation | Set-Content -Path $ExportPath -Encoding UTF8 }
            default { throw "Formato no soportado: $ext. Use .csv o .json." }
        }
        Write-Host "Reporte exportado a: $ExportPath" -ForegroundColor Green
    }

    # Exit code para monitoreo
    if ($ExitOnStale -and $staleCount -gt 0) { exit 1 }
    exit 0
    }
    catch {
        Write-Error "Get-VMwareSnapshotAudit falló: $($_.Exception.Message)"
        exit 2
    }
    finally {
        if ($viServer) {
            Disconnect-VIServer -Server $viServer -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
}
