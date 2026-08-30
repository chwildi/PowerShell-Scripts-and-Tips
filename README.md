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
| `Examples/` | Sanitized example configurations and usage scenarios |
| `Tests/` | Pester and validation tests |
| `Templates/` | Standard PowerShell script template and documentation |
| `docs/` | Coding standards and repository documentation |

## Script categories

`Scripts/` is organized into Active Directory, Microsoft 365, Windows Server, Windows Client, Hyper-V, Security, PKI, Network, Backup, Migration and Utilities. Each technology area contains additional subcategories for easier navigation.

## Tips categories

`Tips/` contains Active Directory, Microsoft 365, PowerShell, Windows, Security and Troubleshooting notes.

## Start a new script

Use [`Templates/PowerShell-Script-Template.ps1`](Templates/PowerShell-Script-Template.ps1) as the standard starting point and read [`Templates/README.md`](Templates/README.md) before publishing a new script.

## Script quality standard

Scripts published in this repository should include clear comment-based help, prerequisites, parameters, examples, error handling and logging where appropriate. Destructive or modifying operations should support safe preview mechanisms such as `-WhatIf` whenever technically possible.

## Security and privacy

Never publish customer-specific or confidential information. Before committing a script, remove or replace passwords, API keys, access tokens, tenant IDs, customer names, internal domains, host names, sensitive IP addresses, e-mail addresses, private certificate material and environment-specific paths.

See [SECURITY.md](SECURITY.md), [CONTRIBUTING.md](CONTRIBUTING.md) and [docs/Coding-Standards.md](docs/Coding-Standards.md).

## Requirements

Most modern scripts target PowerShell 7 where possible. Some Windows administration functions require Windows PowerShell 5.1 or Windows-specific modules such as ActiveDirectory. Each script must document its own requirements.

## Disclaimer

The scripts and examples are provided without warranty. Always review and test code before using it in a production environment. You are responsible for validating compatibility, security and the impact of commands in your own environment.

## License

This repository is distributed under the license contained in [LICENSE](LICENSE).
