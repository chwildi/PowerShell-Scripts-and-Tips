# PowerShell Script Catalog

Central catalog for scripts published in this repository.

## Status model

| Status | Meaning |
|---|---|
| Experimental | Early development; lab use only |
| Testing | Functional testing and review in progress |
| Stable | Reviewed and suitable for controlled production use |
| Deprecated | Retained for reference; replacement recommended |

## Quality indicators

Each script should document: PowerShell version, prerequisites, configuration, administrative rights, WhatIf support, test script, PSScriptAnalyzer status, security considerations and documentation.

## Migration

| Script | Purpose | Version | PowerShell | Status | WhatIf | Test | Risk | Documentation |
|---|---|---:|---:|---|---|---|---|---|
| [Migriere-WindowsBenutzer.ps1](Scripts/Migration/Migriere-WindowsBenutzer.ps1) | Backup and restore local Windows user data for client/domain migrations | 2.0.0.0 | 7+ | Stable | Yes | [TEST](Tests/Migration/Migriere-WindowsBenutzer-TEST.ps1) | Medium | [Guide](docs/Migriere-WindowsBenutzer.md) |

## Categories

- Active Directory
- Backup
- Hyper-V
- Microsoft 365 / Entra ID
- Migration
- Network
- PKI
- Security
- Utilities
- Windows Client
- Windows Server

## Publication checklist

Before a script is marked Stable:

- Customer-neutral configuration and examples
- Safe Configuration Block near the beginning
- Safe no-parameter execution
- Optional parameter overrides
- PowerShell 7 compatibility where technically possible
- Comment-based help and examples
- Error handling and logging where appropriate
- WhatIf/ShouldProcess for modifying operations where possible
- Matching `-TEST.ps1`
- PSScriptAnalyzer review
- Secret/customer-data/security review
- Documentation
- Live/lab test where infrastructure access is required

This catalog should be updated whenever a script is added, renamed, deprecated or receives a new release.
