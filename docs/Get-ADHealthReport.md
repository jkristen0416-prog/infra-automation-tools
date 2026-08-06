# Get-ADHealthReport.ps1

Reporte de salud de Active Directory con controles operativos básicos.

## Descripción

Realiza comprobaciones sobre el estado del dominio y las genera en un único
reporte:

- Controladores de dominio disponibles y habilitados
- Estado de replicación (vía `repadmin /replsummary`)
- Total de cuentas de usuario
- Cuentas deshabilitadas
- Cuentas expiradas
- Contraseñas que nunca expiran
- Contraseñas próximas a expirar (según `maxPwdAge` del dominio)
- Antigüedad del último backup de AD (atributo `lastBackupTime`)
- Exit code para integración con monitoreo

## Requisitos

| Requisito | Detalle |
|---|---|
| Módulo `ActiveDirectory` | RSAT-AD-PowerShell instalado, o ejecución desde un equipo con el módulo |
| Permisos | Lectura sobre AD (usuario de dominio estándar suele bastar) |
| `repadmin.exe` | Opcional — solo para el chequeo de replicación (está en los DCs) |
| PowerShell | 5.1+ o PowerShell 7 (Core) |

## Instalación

El script no requiere instalación. Descargarlo y ejecutarlo:

```powershell
# Descargar
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/jkristen0416-prog/infra-automation-tools/main/scripts/Get-ADHealthReport.ps1" -OutFile "Get-ADHealthReport.ps1"

# Ejecutar
.\Get-ADHealthReport.ps1
```

## Parámetros

| Parámetro | Tipo | Obligatorio | Por defecto | Descripción |
|---|---|---|---|---|
| `-DomainController` | string | No | DC del sitio | Nombre o IP del DC a consultar |
| `-Credential` | PSCredential | No | Sesión actual | Credencial con permisos de lectura |
| `-ExpiryWarningDays` | int | No | 14 | Días previos al vencimiento para marcar "próxima a expirar" |
| `-ExportPath` | string | No | — | Ruta de exportación (`.csv` o `.json`) |
| `-IncludeDisabledUsers` | switch | No | — | Muestra el detalle de cuentas deshabilitadas |
| `-EnableException` | switch | No | — | Lanza excepción terminal en lugar de error no terminante |

## Ejemplos

### Básico (DC del sitio actual)

```powershell
.\Get-ADHealthReport.ps1
```

### Con DC específico y exportación JSON

```powershell
.\Get-ADHealthReport.ps1 -DomainController dc01.corp.local -ExportPath "C:\Reports\ad-health.json"
```

### Con credenciales explícitas y umbral personalizado

```powershell
.\Get-ADHealthReport.ps1 -Credential (Get-Credential) -ExpiryWarningDays 7 -ExportPath "D:\Audit\ad-health.csv"
```

### Ejemplo de salida (datos ficticios)

```
GeneratedAt           : 2026-08-06 09:30:00
Domain                : corp.local
DomainMode            : Windows2016Domain
ForestMode            : Windows2016Forest
TotalDCs              : 3
OnlineDCs             : 3
DCList                : {dc01, dc02, dc03}
TotalUsers            : 1240
DisabledUsers         : 18
ExpiredAccounts       : 0
NeverExpirePasswords  : 7
PasswordsExpiringSoon : 23
MaxPasswordAgeDays    : 60
ExpiryWarningDays     : 14
LastADBackup          : 2026-08-05 22:00:00
ReplicationStatus     : OK
ReplicationDetail     : Destination DC01 DC02 ... LargestDelta 0m ...

Estado general: OK
```

> ⚠️ Los datos de ejemplo son ficticios y demostrativos. Reemplazarlos por la
> salida real del entorno.

## Manejo de errores

| Escenario | Comportamiento |
|---|---|
| Módulo AD no instalado | Error claro indicando instalar RSAT-AD-PowerShell |
| DC inaccesible | Error de conexión con el mensaje de la excepción |
| `repadmin` ausente | El campo `ReplicationStatus` indica que no está disponible (no aborta) |
| Formato de exportación inválido | Error indicando usar `.csv` o `.json` |
| Fallo general | `Write-Error` + exit code 2 |

## Exit codes

| Código | Significado |
|---|---|
| 0 | Estado general OK |
| 1 | Revisión requerida (DC caído, replicación con problemas o cuentas expiradas) |
| 2 | Error de ejecución |

## Capturas

> ⏳ Pendiente: agregar captura real de la ejecución en el entorno de
> producción. Colocar el archivo en `docs/screenshots/ad-health-report.png`
> y referenciarlo aquí.

## Consideraciones de seguridad

- No almacenar credenciales en el script; usar `-Credential` o sesión
  interactiva (ej: `Get-Credential`).
- El export contiene información de cuentas del dominio (nombres,
  `SamAccountName`, `DistinguishedName`). Proteger el archivo resultante y
  no publicarlo.
- Usar una cuenta con el **mínimo privilegio necesario** (lectura sobre AD).
- Los valores `lastBackupTime` revelan la cadencia de backup: tratar el
  reporte como información interna.
- Antes de ejecutar en producción, validar en un entorno de laboratorio o
  contra un DC secundario.
