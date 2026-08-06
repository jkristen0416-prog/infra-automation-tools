# Test-BackupFreshness.ps1

Verificación de frescura y vigencia de backups.

## Descripción

Escanea rutas de backup (carpetas o archivos individuales) y verifica que el
elemento más reciente no supere una antigüedad máxima configurada. Cada ruta
se marca como `OK`, `VENCIDO`, `SIN ARCHIVOS` o `RUTA INEXISTENTE`.

Diseñado para integrarse con monitoreo y tareas programadas mediante exit
codes:

- **0** — todo al día
- **1** — backups vencidos
- **2** — error de ejecución

Útil para validar backups de Veeam, carpetas de copia a NAS, dumps SQL,
exports de configuración, etc.

## Requisitos

| Requisito | Detalle |
|---|---|
| Permisos | Lectura sobre las rutas a verificar |
| Rutas UNC | Cuenta con acceso a la red, o `New-SmbMapping` previo |
| PowerShell | 5.1+ o PowerShell 7 (Core) |

## Instalación

```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/jkristen0416-prog/infra-automation-tools/main/scripts/Test-BackupFreshness.ps1" -OutFile "Test-BackupFreshness.ps1"
```

## Parámetros

| Parámetro | Tipo | Obligatorio | Por defecto | Descripción |
|---|---|---|---|---|
| `-Path` | string[] | **Sí** | — | Rutas a verificar (carpetas o archivos) |
| `-MaxAgeHours` | int | No | 24 | Antigüedad máxima permitida en horas |
| `-Pattern` | string | No | `*` | Filtro de archivos dentro de carpetas |
| `-ExportPath` | string | No | — | Exportación (`.csv` o `.json`) |
| `-ExitOnStale` | switch | No | — | Exit code 1 si hay backups vencidos |

## Ejemplos

### Verificación básica de una carpeta (máx. 24 h)

```powershell
.\Test-BackupFreshness.ps1 -Path "D:\Backups\Veeam"
```

### Múltiples rutas, patrón específico y alerta por exit code

```powershell
.\Test-BackupFreshness.ps1 -Path "D:\Backups\Veeam","E:\Backups\SQL" -Pattern "*.vbk" -MaxAgeHours 36 -ExitOnStale
```

### Rutas UNC y exportación JSON para dashboard

```powershell
.\Test-BackupFreshness.ps1 -Path "\\nas01\backups\veeam" -MaxAgeHours 48 -ExportPath "C:\Reports\backup-freshness.json"
```

### Ejemplo de salida (datos ficticios)

```
Path                    LatestFile      LastWrite           AgeHours Status
----                    ----------      ---------           -------- ------
D:\Backups\Veeam        backup-08-05.vbk 2026-08-05 22:00:00  12.5    OK
E:\Backups\SQL          full-2026-07-30.bak 2026-07-30 02:15:00 170.2  VENCIDO
\\nas01\backups\config  router.rsc      2026-08-06 06:00:00   3.0     OK

ALERTA: 1 backup(s) vencido(s) (mayores a 24 horas).
```

> ⚠️ Los datos de ejemplo son ficticios y demostrativos. Reemplazarlos por la
> salida real del entorno.

## Uso con Task Scheduler (Windows)

1. Crear una tarea programada que ejecute:

   ```
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\Test-BackupFreshness.ps1" -Path "D:\Backups\Veeam" -MaxAgeHours 24 -ExitOnStale
   ```

2. Configurar la tarea para que, si el comando devuelve código 1, envíe una
   alerta (correo, webhook, evento de aplicación).

## Manejo de errores

| Escenario | Comportamiento |
|---|---|
| Ruta inexistente | Marca la fila como `RUTA INEXISTENTE`, continúa con las demás |
| Carpeta sin archivos que coincidan | Marca `SIN ARCHIVOS`, continúa |
| Sin permisos sobre la ruta | `Write-Warning` + fila con estado de problema |
| Formato de exportación inválido | Error indicando usar `.csv` o `.json` |
| Fallo general | `Write-Error` + exit code 2 |

## Exit codes

| Código | Significado |
|---|---|
| 0 | Todos los backups al día |
| 1 | Al menos un backup vencido (con `-ExitOnStale`) o rutas con problemas |
| 2 | Error de ejecución |

## Capturas

> ⏳ Pendiente: agregar captura real de la ejecución en el entorno de
> producción. Colocar el archivo en `docs/screenshots/backup-freshness.png`
> y referenciarlo aquí.

## Consideraciones de seguridad

- No almacenar credenciales en el script; ejecutarlo con una cuenta de
  servicio con permisos mínimos de lectura sobre las rutas.
- En rutas UNC, la cuenta de servicio debe tener acceso SMB; usar
  `New-SmbMapping` o un `Logon Session` dedicado — no credenciales en texto
  plano.
- Los reportes revelan la topología de backups (rutas, nombres, cadencia):
  proteger el export y no publicarlo.
- Un backup "al día" según antigüedad no garantiza integridad: combinar con
  restauraciones de prueba periódicas.
