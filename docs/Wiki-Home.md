# PowerShell Scripts & Tips — Wiki Home

Welcome to the knowledge base for this PowerShell repository. This documentation is maintained together with the source code so changes can be reviewed and versioned.

## Start here

- [Script Catalog](../SCRIPT-CATALOG.md) — all published scripts and quality status
- [Repository README](../README.md) — repository purpose and structure
- [Security Policy](../SECURITY.md) — security and responsible reporting
- [Contributing](../CONTRIBUTING.md) — contribution rules
- [Coding Standards](Coding-Standards.md) — development standards

## Script documentation

### Migration

- [Migriere-WindowsBenutzer](Migriere-WindowsBenutzer.md) — Windows user-data backup and restore for migration scenarios

## Quality model

Every production-oriented script should move through these stages:

`Idea -> Development -> Testing -> Security Review -> Ready -> Published -> Maintenance`

A script should only be considered Stable after code review, static analysis, security/privacy review, matching tests, documentation and appropriate live/lab validation.

## Recommended Project board

Use one central GitHub Project named **PowerShell Development** instead of a separate Project for every script.

Recommended fields:

- Status
- Script / Component
- Category
- Priority
- Risk
- Version
- PowerShell compatibility
- Test status
- Security review
- Documentation status
- Target release

Recommended views:

1. Development Board — grouped by Status
2. Script Roadmap — grouped by Category
3. Security Review — scripts awaiting security/privacy review
4. Testing — scripts awaiting automated or live tests
5. Releases — items grouped by target release
6. Maintenance — Stable scripts with bugs or improvements

## Issue strategy

Use Issues as the work items connected to the Project. Recommended issue types/templates:

- New Script Proposal
- Bug Report
- Feature / Improvement
- Security Hardening
- Documentation
- Testing / Compatibility

## Repository roadmap

Next improvements recommended:

1. GitHub Actions for syntax, PSScriptAnalyzer and tests
2. Issue and pull-request templates
3. Automated catalog validation
4. CHANGELOG and release/tag convention
5. Compatibility matrix
6. Reusable module extraction for shared functions
7. Deprecated archive and replacement links
8. Sanitized examples for common customer scenarios

## Wiki publishing note

The files under `docs/` are the canonical, version-controlled knowledge base. They can also be mirrored into GitHub Wiki pages. Keeping the source in the repository prevents Wiki documentation from drifting away from the scripts.
