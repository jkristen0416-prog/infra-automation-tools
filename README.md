# infra-automation-tools

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
├── docs/
│   ├── Get-ADHealthReport.md         # Documentación completa de la herramienta
│   ├── Get-VMwareSnapshotAudit.md
│   └── Test-BackupFreshness.md
└── .github/workflows/
    └── lint.yml                      # Validación automática (CI)
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

## Validación automática (CI)

Cada push ejecuta GitHub Actions con:

- **PSScriptAnalyzer** sobre `scripts/*.ps1` (reglas estándar de estilo y
  buenas prácticas PowerShell)
- **markdownlint** sobre la documentación

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
