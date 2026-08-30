# PowerShell Scripts & Tips

Practical PowerShell scripts, tips, examples and best practices for Windows, Active Directory, Microsoft 365, Entra ID, Hyper-V, PKI and IT Security.

> **Important:** Review every script before using it in production. Test first in a lab or non-production environment and adapt configuration values to your environment.

## Repository structure

| Area | Content |
|---|---|
| `Scripts/` | Complete PowerShell scripts grouped by technology |
| `Tips/` | Short guides, troubleshooting notes and best practices |
| `Snippets/` | Small reusable PowerShell examples and one-liners |
| `Modules/` | Reusable PowerShell modules and functions |
| `Examples/` | Example configurations and usage scenarios |
| `Tests/` | Pester and validation tests |
| `docs/` | Documentation, standards and templates |

## Main topics

- Active Directory administration, migration and security
- Microsoft 365 and Entra ID
- Exchange Online, Intune, Teams and SharePoint
- Windows Server and Windows Client
- Hyper-V and virtualization
- PKI and Active Directory Certificate Services
- Security auditing and hardening
- Network administration and diagnostics
- Backup, migration and automation
- General PowerShell utilities and troubleshooting

## Script quality standard

Scripts published in this repository should include clear comment-based help, prerequisites, parameters, examples, error handling and logging where appropriate. Destructive operations should support safe preview mechanisms such as `-WhatIf` whenever technically possible.

## Security and privacy

Never publish customer-specific or confidential information. Before committing a script, remove or replace passwords, API keys, access tokens, tenant IDs, customer names, internal domains, public/private IP addresses, e-mail addresses, certificate secrets and environment-specific paths.

See [SECURITY.md](SECURITY.md) for the repository security policy and [CONTRIBUTING.md](CONTRIBUTING.md) for contribution and publishing guidelines.

## Requirements

Most modern scripts target PowerShell 7 where possible. Some Windows administration functions require Windows PowerShell 5.1 or Windows-specific modules such as ActiveDirectory.

Each script should document its own requirements.

## Disclaimer

The scripts and examples are provided without warranty. Always review and test code before using it in a production environment. You are responsible for validating compatibility, security and the impact of commands in your own environment.

## License

This repository is distributed under the license contained in [LICENSE](LICENSE).
