<#
.SYNOPSIS
    Genera un reporte de salud de Active Directory con controles operativos básicos.

.DESCRIPTION
    Realiza un conjunto de comprobaciones sobre el estado de Active Directory:
    controladores de dominio disponibles, estado de replicación, cuentas
    deshabilitadas, cuentas expiradas, contraseñas próximas a expirar y
    antigüedad del último backup del estado del sistema.

    El reporte se muestra por consola y puede exportarse a CSV o JSON para
    integración con sistemas de monitoreo o programación de tareas.

.PARAMETER DomainController
    Nombre o dirección IP del controlador de dominio a consultar.
    Si se omite, se usa el DC disponible más cercano.

.PARAMETER Credential
    Credencial con permisos de lectura sobre Active Directory.
    Si se omite, se usa la sesión actual.

.PARAMETER ExpiryWarningDays
    Días antes del vencimiento para marcar una contraseña como "próxima a expirar".
    Valor por defecto: 14.

.PARAMETER ExportPath
    Ruta completa del archivo de exportación (.csv o .json).
    Si se omite, el reporte solo se muestra por consola.

.PARAMETER IncludeDisabledUsers
    Incluye el detalle de cuentas de usuario deshabilitadas.
    Por defecto solo se muestra el conteo.

.PARAMETER EnableException
    Lanza una excepción terminal en lugar de escribir un error no terminante.

.EXAMPLE
    # Reporte básico contra el DC del sitio actual
    .\Get-ADHealthReport.ps1

.EXAMPLE
    # Reporte con exportación JSON hacia un path de monitoreo
    .\Get-ADHealthReport.ps1 -DomainController dc01.corp.local -ExportPath "C:\Reports\ad-health.json"

.EXAMPLE
    # Con credenciales explícitas y umbral de expiración personalizado
    .\Get-ADHealthReport.ps1 -Credential (Get-Credential) -ExpiryWarningDays 7 -ExportPath "D:\Audit\ad-health.csv"

.NOTES
    Requisitos:
    - Módulo ActiveDirectory (RSAT-AD-PowerShell) o equipo con acceso al DC.
    - Permisos de lectura sobre AD (usuarios del dominio estándar suelen bastar).

    Seguridad:
    - No almacenar credenciales en el script; usar -Credential o sesión interactiva.
    - El export contiene información de cuentas; proteger el archivo resultante.

    Autor: jkristen
    Versión: 1.0.0
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$DomainController,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.PSCredential]$Credential,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 365)]
    [int]$ExpiryWarningDays = 14,

    [Parameter(Mandatory = $false)]
    [string]$ExportPath,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeDisabledUsers,

    [Parameter(Mandatory = $false)]
    [switch]$EnableException
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Assert-ADModule {
    if (-not (Get-Module -Name ActiveDirectory -ListAvailable)) {
        throw "El módulo ActiveDirectory no está disponible. Instale RSAT-AD-PowerShell o ejecute en un equipo con el módulo."
    }
    Import-Module -Name ActiveDirectory -ErrorAction Stop
}

function Get-ADSessionParameter {
    param(
        [string]$Server,
        [System.Management.Automation.PSCredential]$Cred
    )
    $params = @{}
    if ($Server) { $params['Server'] = $Server }
    if ($Cred) { $params['Credential'] = $Cred }
    return $params
}

function ConvertTo-ReportDate {
    param([datetime]$Value)
    return $Value.ToString('yyyy-MM-dd HH:mm:ss')
}

function Get-ExpiredPasswordUser {
    <#
    .SYNOPSIS
        Calcula los usuarios con contraseña ya vencida (antigüedad >= maxPwdAge).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Users,

        [Parameter(Mandatory = $false)]
        [int]$MaxAgeDays,

        [Parameter(Mandatory = $false)]
        [datetime]$Now = (Get-Date)
    )

    if (-not $MaxAgeDays) { return @() }

    # Filtrar primero los que tienen PasswordLastSet (evita $Now - $null)
    return @($Users | Where-Object { $_.PasswordLastSet } | ForEach-Object {
        $ageDays = ($Now - $_.PasswordLastSet).TotalDays
        if (-not $_.PasswordNeverExpires -and
            $_.Enabled -and
            $ageDays -ge $MaxAgeDays) {
            $_
        }
    })
}

function Get-DomainMaxPasswordAge {
    <#
    .SYNOPSIS
        Obtiene la antigüedad máxima de contraseña del dominio en días.
        Prioriza Get-ADDefaultDomainPasswordPolicy (vía oficial de Microsoft)
        con fallback a Get-ADDomain.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [hashtable]$SessionParams = @{},

        [Parameter(Mandatory = $false)]
        [object]$DomainInfo
    )

    try {
        $passwordPolicy = Get-ADDefaultDomainPasswordPolicy @SessionParams -ErrorAction Stop
        $maxPwdAge = $passwordPolicy.MaxPasswordAge
        if (-not $maxPwdAge -and $DomainInfo) {
            $maxPwdAge = $DomainInfo.MaxPasswordAge
        }
        if ($maxPwdAge -and $maxPwdAge.TotalDays -gt 0) {
            return [math]::Floor($maxPwdAge.TotalDays)
        }
    }
    catch {
        Write-Warning "No se pudo obtener MaxPasswordAge (Get-ADDefaultDomainPasswordPolicy): $($_.Exception.Message)"
        if ($DomainInfo -and $DomainInfo.MaxPasswordAge) {
            return [math]::Floor($DomainInfo.MaxPasswordAge.TotalDays)
        }
    }
    return $null
}

function Get-PasswordExpiringUser {
    <#
    .SYNOPSIS
        Calcula los usuarios con contraseña próxima a expirar según la
        antigüedad máxima del dominio y el umbral de advertencia.

    .NOTES
        Usa la política predeterminada del dominio. Las Fine-Grained
        Password Policies (FGPP) pueden aplicar políticas distintas a
        subconjuntos de usuarios y no se consideran en este cálculo.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Users,

        [Parameter(Mandatory = $false)]
        [int]$MaxAgeDays,

        [Parameter(Mandatory = $false)]
        [int]$ExpiryWarningDays = 14,

        [Parameter(Mandatory = $false)]
        [datetime]$Now = (Get-Date)
    )

    if (-not $MaxAgeDays) { return @() }

    # Filtrar primero los que tienen PasswordLastSet (evita $Now - $null)
    return @($Users | Where-Object { $_.PasswordLastSet } | ForEach-Object {
        $ageDays = ($Now - $_.PasswordLastSet).TotalDays
        if (-not $_.PasswordNeverExpires -and
            $_.Enabled -and
            $ageDays -ge ($MaxAgeDays - $ExpiryWarningDays) -and
            $ageDays -lt $MaxAgeDays) {
            $_
        }
    })
}

# ---------------------------------------------------------------------------
# Main (se omite al dot-sourcear para permitir pruebas con Pester)
# ---------------------------------------------------------------------------

if ($MyInvocation.InvocationName -ne '.') {
    try {
        Assert-ADModule
        $session = Get-ADSessionParameter -Server $DomainController -Cred $Credential

        Write-Verbose "Recopilando estado del dominio..."
        $domainInfo = Get-ADDomain @session

        Write-Verbose "Enumerando controladores de dominio..."
        $dcs = Get-ADDomainController -Filter * @session

    $now = Get-Date
    $report = [ordered]@{
        GeneratedAt        = ConvertTo-ReportDate $now
        Domain             = $domainInfo.DNSRoot
        DomainMode         = $domainInfo.DomainMode
        ForestMode         = $domainInfo.ForestMode
        TotalDCs           = @($dcs).Count
        EnabledDCs         = @($dcs | Where-Object { $_.IsEnabled }).Count
        DCList             = @($dcs | ForEach-Object { $_.Name })
    }

    Write-Verbose "Consultando cuentas de usuario..."
    $allUsers = Get-ADUser -Filter * -Properties PasswordLastSet, PasswordNeverExpires, Enabled, AccountExpirationDate, LastLogonDate @session

    $disabled   = @($allUsers | Where-Object { -not $_.Enabled })
    $expired    = @($allUsers | Where-Object { $_.AccountExpirationDate -and $_.AccountExpirationDate -lt $now })
    $noExpire   = @($allUsers | Where-Object { $_.PasswordNeverExpires })

    # Contraseñas próximas a expirar: se calcula contra el maxPwdAge del dominio.
    # Prioridad: Get-ADDefaultDomainPasswordPolicy (vía oficial de Microsoft),
    # con fallback a Get-ADDomain. Nota: las Fine-Grained Password Policies
    # (FGPP) pueden aplicar políticas distintas a subconjuntos de usuarios;
    # este cálculo usa la política predeterminada del dominio.
    $maxPwdAgeDays = Get-DomainMaxPasswordAge -SessionParams $session -DomainInfo $domainInfo

    $passwordExpiring = @(Get-PasswordExpiringUser -Users $allUsers -MaxAgeDays $maxPwdAgeDays -ExpiryWarningDays $ExpiryWarningDays -Now $now)
    $expiredPasswords = @(Get-ExpiredPasswordUser -Users $allUsers -MaxAgeDays $maxPwdAgeDays -Now $now)

    $report['TotalUsers']          = @($allUsers).Count
    $report['DisabledUsers']       = @($disabled).Count
    $report['ExpiredAccounts']     = @($expired).Count
    $report['ExpiredPasswords']    = @($expiredPasswords).Count
    $report['NeverExpirePasswords']= @($noExpire).Count
    $report['PasswordsExpiringSoon'] = @($passwordExpiring).Count
    $report['MaxPasswordAgeDays']  = $maxPwdAgeDays
    $report['ExpiryWarningDays']   = $ExpiryWarningDays

    Write-Verbose "Intentando consultar fecha de último backup de AD (atributo lastBackupTime)..."
    # Nota: lastBackupTime es un atributo best-effort del objeto domainDNS.
    # No está garantizado en todos los entornos (depende de cómo se realicen
    # los backups); este bloque intenta consultarlo cuando está disponible y
    # no debe considerarse un control definitivo de vigencia de backup.
    try {
        $lastBackup = Get-ADObject -Filter "objectClass -eq 'domainDNS'" -Properties lastBackupTime @session
        if ($lastBackup.lastBackupTime) {
            $report['LastADBackup'] = ConvertTo-ReportDate ([datetime]$lastBackup.lastBackupTime)
        }
        else {
            $report['LastADBackup'] = 'Sin registro (verificar política de backup)'
        }
    }
    catch {
        $report['LastADBackup'] = "No consultable: $($_.Exception.Message)"
    }

    Write-Verbose "Comprobando replicación (repadmin)..."
    if (Get-Command repadmin.exe -ErrorAction SilentlyContinue) {
        $repOut = repadmin.exe /replsummary 2>&1 | Out-String
        $repInProgress = $repOut -match 'in progress|FAIL|error'
        $report['ReplicationStatus'] = if ($repInProgress) { 'ATENCION - revisar /replsummary' } else { 'OK' }
        $report['ReplicationDetail'] = ($repOut -replace '\s+', ' ').Trim()
    }
    else {
        $report['ReplicationStatus'] = 'repadmin no disponible en este equipo'
        $report['ReplicationDetail'] = ''
    }

    # Resultado consolidado
    $ok = ($report['EnabledDCs'] -eq $report['TotalDCs']) -and
          ($report['ReplicationStatus'] -eq 'OK') -and
          ($report['ExpiredAccounts'] -eq 0)

    $result = [PSCustomObject]$report
    $result | Format-List | Out-String | Write-Output

    Write-Host "`nEstado general: $(if ($ok) { 'OK' } else { 'REVISION REQUERIDA' })" -ForegroundColor $(if ($ok) { 'Green' } else { 'Yellow' })

    # Detalle opcional de cuentas deshabilitadas
    if ($IncludeDisabledUsers -and $disabled.Count -gt 0) {
        Write-Host "`nCuentas deshabilitadas ($($disabled.Count)):" -ForegroundColor Cyan
        $disabled | Select-Object Name, SamAccountName, DistinguishedName | Format-Table -AutoSize
    }

    # Exportación
    if ($ExportPath) {
        $exportObj = [PSCustomObject]@{
            Report        = $result
            ExpiringUsers = $passwordExpiring | Select-Object Name, SamAccountName, PasswordLastSet, PasswordNeverExpires
        }

        $ext = [System.IO.Path]::GetExtension($ExportPath).ToLowerInvariant()
        switch ($ext) {
            '.json' { $exportObj | ConvertTo-Json -Depth 4 | Set-Content -Path $ExportPath -Encoding UTF8 }
            '.csv'  { $exportObj.Report | ConvertTo-Csv -NoTypeInformation | Set-Content -Path $ExportPath -Encoding UTF8 }
            default { throw "Formato no soportado: $ext. Use .csv o .json." }
        }
        Write-Host "Reporte exportado a: $ExportPath" -ForegroundColor Green
    }

    # Exit code para monitoreo
    if ($ok) { exit 0 } else { exit 1 }
    }
    catch {
        if ($EnableException) {
            throw
        }
        Write-Error "Get-ADHealthReport falló: $($_.Exception.Message)"
        exit 2
    }
}
