# infra-automation-tools

[![CI](https://github.com/jkristen0416-prog/infra-automation-tools/actions/workflows/lint.yml/badge.svg)](https://github.com/jkristen0416-prog/infra-automation-tools/actions/workflows/lint.yml)

Herramientas de automatización para controles operativos, auditorías y
administración de infraestructura.

> Colección de scripts PowerShell enfocados en tareas repetitivas de
> operaciones: reportes de salud, auditorías y verificaciones. Diseñados
> para ejecución manual o programada, con exportación a CSV/JSON y exit
> codes para integración con monitoreo.

## Estructura

```text
├── scripts/
│   ├── Get-ADHealthReport.ps1        # Reporte de salud de Active Directory
│   ├── Get-VMwareSnapshotAudit.ps1   # Auditoría de snapshots vSphere
│   └── Test-BackupFreshness.ps1      # Verificación de vigencia de backups
├── tests/
│   ├── Get-ADHealthReport.Tests.ps1  # Tests Pester (mocks de cmdlets AD)
│   ├── Get-VMwareSnapshotAudit.Tests.ps1
│   ├── Test-BackupFreshness.Tests.ps1
│   └── run-tests.ps1                 # Runner local de tests
├── docs/
│   ├── Get-ADHealthReport.md         # Documentación completa de la herramienta
│   ├── Get-VMwareSnapshotAudit.md
│   └── Test-BackupFreshness.md
└── .github/workflows/
    └── lint.yml                      # CI: lint + tests
```

## Herramientas

| Herramienta | Área | Propósito | Documentación |
| --- | --- | --- | --- |
| `Get-ADHealthReport.ps1` | Active Directory | Estado del dominio: DCs, replicación, cuentas, expiración de contraseñas, último backup | [docs](docs/Get-ADHealthReport.md) |
| `Get-VMwareSnapshotAudit.ps1` | VMware vSphere | Snapshots antiguos por VM, tamaño y alerta de consolidación | [docs](docs/Get-VMwareSnapshotAudit.md) |
| `Test-BackupFreshness.ps1` | Backups | Antigüedad del backup más reciente por ruta, con exit code para monitoreo | [docs](docs/Test-BackupFreshness.md) |

## Requisitos generales

- **PowerShell 5.1+** o PowerShell 7 (Core)
- Módulos específicos por herramienta (detallados en cada `docs/`):
  - AD: módulo `ActiveDirectory` (RSAT)
  - VMware: `VMware.PowerCLI`
  - Backups: ninguno adicional

## Uso rápido

```powershell
# Reporte de salud de AD (consola)
.\scripts\Get-ADHealthReport.ps1

# Auditoría de snapshots (umbral 7 días, alerta por exit code)
.\scripts\Get-VMwareSnapshotAudit.ps1 -VCenter vc01.corp.local -MaxAgeDays 7 -ExitOnStale

# Verificación de backups (rutas separadas por coma)
.\scripts\Test-BackupFreshness.ps1 -Path "D:\Backups\Veeam" -MaxAgeHours 24 -ExitOnStale
```

## Exit codes (integración con monitoreo)

| Código | Significado |
| --- | --- |
| 0 | Todo correcto / sin hallazgos |
| 1 | Hallazgo que requiere atención (snapshot vencido, backup vencido, AD con revisión) |
| 2 | Error de ejecución |

## Salida de demostración generada mediante una ejecución real

> Los resultados fueron generados ejecutando las herramientas en un entorno
> controlado con rutas, nombres y datos ficticios.

### Flujo de operación

```text
┌───────────────┐     ┌──────────────────────┐     ┌──────────────────┐
│ Infraestructura│──▶ │ Script (PowerShell)  │──▶ │ Reporte          │
│ (AD, vSphere,  │     │ CSV/JSON + exit code │     │ Consola / archivo│
│  Backups)      │     └──────────────────────┘     └────────┬─────────┘
└───────────────┘                                          │
                                                            ▼
                                             ┌──────────────────────┐
                                             │ Monitoreo / scheduler │
                                             │ (exit code ≠ 0 = alerta)│
                                             └──────────────────────┘
```

### Consola (Test-BackupFreshness.ps1 — ejecución real)

```text
Path                  LatestFile            LastWrite           AgeHours Status
----                  ----------            ---------           -------- ------
/backups/veeam        backup-2026-08-06.vbk 2026-08-06 10:21:23     3.70 OK
/backups/sql          full-2026-08-03.bak   2026-08-03 12:21:23    73.70 VENCI…

ALERTA: 1 backup(s) vencido(s) (mayores a 24 horas).
```

### Exportación JSON (Test-BackupFreshness.ps1)

```json
[
  {
    "Path": "/backups/veeam",
    "LatestFile": "backup-2026-08-06.vbk",
    "LastWrite": "2026-08-06 10:21:23",
    "AgeHours": 3.7,
    "MaxAgeHours": 24,
    "Status": "OK"
  },
  {
    "Path": "/backups/sql",
    "LatestFile": "full-2026-08-03.bak",
    "LastWrite": "2026-08-03 12:21:23",
    "AgeHours": 73.7,
    "MaxAgeHours": 24,
    "Status": "VENCIDO"
  }
]
```

### Exportación CSV (Test-BackupFreshness.ps1)

```csv
"Path","LatestFile","LastWrite","AgeHours","MaxAgeHours","Status"
"/backups/veeam","backup-2026-08-06.vbk","2026-08-06 10:21:23","3.7","24","OK"
"/backups/sql","full-2026-08-03.bak","2026-08-03 12:21:23","73.7","24","VENCIDO"
```

> ⚠️ Rutas y nombres de archivo son ficticios (entorno de demostración).
> Cada `docs/` incluye la salida de demostración de su herramienta.

## Validación automática (CI)

Cada push ejecuta GitHub Actions con:

- **PSScriptAnalyzer** sobre `scripts/*.ps1` (reglas estándar de estilo y
  buenas prácticas PowerShell)
- **Pester** sobre `tests/*.Tests.ps1` (tests de comportamiento con mocks de
  los cmdlets externos: AD, VMware PowerCLI y sistema de archivos)
- **markdownlint** sobre la documentación

Ejecución local de los tests:

```powershell
pwsh -File .\tests\run-tests.ps1
```

Ver el workflow en [.github/workflows/lint.yml](.github/workflows/lint.yml).

## Seguridad

- Los scripts **no almacenan credenciales**. Usar `-Credential` o la sesión
  actual.
- Ningún ejemplo de este repositorio contiene datos reales de entornos de
  producción (datos ficticios y anonimizados).
- Ejecutar siempre con cuentas de mínimo privilegio.
- Revisar `docs/` de cada herramienta para las consideraciones de seguridad
  específicas.

## Licencia

MIT — ver [LICENSE](LICENSE).
