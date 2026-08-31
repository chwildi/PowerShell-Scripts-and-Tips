# PowerShell Script Compatibility Matrix

This matrix documents intended and verified compatibility. **Intended** means the script was designed for the platform. **Verified** means it has been executed successfully in an appropriate test/lab environment.

## Legend

| Symbol | Meaning |
|---|---|
| ✅ | Verified |
| 🟡 | Intended / requires validation |
| ❌ | Not supported |
| N/A | Not applicable |

## Scripts

| Script | Windows 10 | Windows 11 | Server 2019 | Server 2022 | Server 2025 | PS 5.1 | PS 7.x | Admin required | External modules |
|---|---|---|---|---|---|---|---|---|---|
| `Migriere-WindowsBenutzer.ps1` | 🟡 | 🟡 | N/A | N/A | N/A | ❌ | 🟡 | Depends on operation | None for core operation |

## Validation status

### Migriere-WindowsBenutzer.ps1 2.0.0.0

- Target: Windows client profile migration scenarios.
- PowerShell target: 7.x.
- Windows 10/11 compatibility is currently marked **Intended / requires validation** until controlled live/lab tests confirm the published version.
- Some operations may require elevation depending on source/destination permissions, printer configuration, Wi-Fi restoration and migration environment.
- Wi-Fi clear-text export must remain explicitly enabled and should be handled as sensitive data.

## Module compatibility

When a script requires an external module, document at minimum:

- Module name
- Minimum/tested version
- Windows-only or cross-platform status
- Required permissions/roles
- Authentication method where applicable

Examples include `ActiveDirectory`, `Microsoft.Graph`, `ExchangeOnlineManagement` and other Microsoft administration modules.

## Rules for new scripts

1. Add every published script to this matrix.
2. Never mark a platform ✅ only because the code appears compatible; successful validation is required.
3. Use 🟡 for designed/intended compatibility that has not yet been proven.
4. Document module and privilege requirements.
5. Update the matrix after compatibility testing or breaking changes.
6. Keep customer-specific infrastructure and identifiers out of this document.
