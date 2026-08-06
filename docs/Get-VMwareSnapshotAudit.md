# Get-VMwareSnapshotAudit.ps1

Auditoría de snapshots en plataformas VMware vCenter.

## Descripción

Se conecta a un vCenter Server y enumera todas las máquinas virtuales con
snapshots, generando un reporte con:

- Nombre de la VM y del snapshot
- Fecha de creación y antigüedad en días
- Tamaño del snapshot (formateado)
- Si el snapshot es el actual (`IsCurrent`)
- Estado: `OK` o `STALE` (supera el umbral configurado)
- Exit code para alertar cuando existen snapshots vencidos

Los snapshots antiguos consumen espacio en datastore y pueden degradar el
rendimiento de la VM. Este script **solo audita**, no elimina nada.

## Requisitos

| Requisito | Detalle |
| --- | --- |
| VMware PowerCLI | `Install-Module VMware.PowerCLI -Scope CurrentUser` |
| Cuenta vCenter | Permiso de **solo lectura** sobre VMs y snapshots |
| PowerShell | 5.1+ o PowerShell 7 (Core) |
| vCenter | 6.5 o superior (probado con vSphere 7) |

## Instalación

```powershell
Install-Module VMware.PowerCLI -Scope CurrentUser
Set-PowerCLIConfiguration -ParticipateInCEIP $false   # opcional

# Descargar el script
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/jkristen0416-prog/infra-automation-tools/main/scripts/Get-VMwareSnapshotAudit.ps1" -OutFile "Get-VMwareSnapshotAudit.ps1"
```

## Parámetros

| Parámetro | Tipo | Obligatorio | Por defecto | Descripción |
| --- | --- | --- | --- | --- |
| `-VCenter` | string | **Sí** | — | FQDN o IP del vCenter |
| `-Credential` | PSCredential | No | Se solicita | Credencial de solo lectura |
| `-MaxAgeDays` | int | No | 30 | Antigüedad máxima aceptable en días |
| `-ExportPath` | string | No | — | Exportación (`.csv` o `.json`) |
| `-ExitOnStale` | switch | No | — | Exit code 1 si hay snapshots STALE |
| `-SkipCertificateCheck` | switch | No | — | Ignora certificados TLS (solo laboratorio) |

## Ejemplos

### Auditoría básica

```powershell
.\Get-VMwareSnapshotAudit.ps1 -VCenter vc01.corp.local
```

### Umbral de 7 días, exportación JSON y alerta por exit code

```powershell
.\Get-VMwareSnapshotAudit.ps1 -VCenter vc01.corp.local -MaxAgeDays 7 -ExportPath "D:\Audit\snapshots.json" -ExitOnStale
```

### Laboratorio con certificado autofirmado

```powershell
.\Get-VMwareSnapshotAudit.ps1 -VCenter 192.168.10.50 -SkipCertificateCheck
```

### Ejemplo de salida (datos ficticios)

```text
GeneratedAt      : 2026-08-06 10:00:00
VCenter          : vc01.corp.local
VMsWithSnapshots : 4
TotalSnapshots   : 6
StaleSnapshots   : 2
MaxAgeDays       : 30
StaleThreshold   : 30 dias

VMName         SnapshotName       AgeDays Size    Status
------         ------------       ------- ----    ------
web-prod-01    pre-upgrade-v2     45.2    12.50 GB STALE
sql-prod-02    parche-2026-05     38.7    8.20 GB  STALE
app-dev-03     baseline          12.4     3.10 GB  OK
app-dev-03     test-migracion     5.1     0.90 GB  OK
dc-01          pre-patch-2026     2.3     4.40 GB  OK

ALERTA: 2 snapshot(s) superan los 30 dias. Revisar y consolidar.
```

> ⚠️ Los datos de ejemplo son ficticios y demostrativos. Reemplazarlos por la
> salida real del entorno.

## Manejo de errores

| Escenario | Comportamiento |
| --- | --- |
| PowerCLI no instalado | Error claro con el comando de instalación |
| Credenciales inválidas | Error de autenticación de PowerCLI |
| vCenter inaccesible | Error de conexión |
| Formato de exportación inválido | Error indicando usar `.csv` o `.json` |
| Fallo general | `Write-Error` + exit code 2 |

## Exit codes

| Código | Significado |
| --- | --- |
| 0 | Sin snapshots STALE (o `-ExitOnStale` no usado) |
| 1 | Existen snapshots STALE y se usó `-ExitOnStale` |
| 2 | Error de ejecución |

## Capturas

> ⏳ Pendiente: agregar captura real de la ejecución en el entorno de
> producción. Colocar el archivo en `docs/screenshots/vmware-snapshot-audit.png`
> y referenciarlo aquí.

## Consideraciones de seguridad

- Usar una cuenta de **solo lectura** sobre el vCenter. Nunca una cuenta de
  administrador completo para auditorías rutinarias.
- `-SkipCertificateCheck` **deshabilita la validación TLS**: usarlo
  únicamente en laboratorio o con certificados autofirmados conocidos.
  Preferir registrar el certificado del vCenter como de confianza.
- El reporte revela nombres de VMs y estructura interna: proteger el export.
- Este script no elimina snapshots. La consolidación de snapshots es una
  operación de impacto y debe hacerse con cambio aprobado y fuera de
  ventanas de servicio críticas.
