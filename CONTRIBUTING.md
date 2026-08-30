# Contributing

Contributions, corrections and improvements are welcome.

## Before publishing

1. Remove all customer-specific and confidential information.
2. Never commit passwords, tokens, API keys or private certificates.
3. Test the script in an appropriate non-production environment.
4. Run PowerShell syntax validation and, where possible, PSScriptAnalyzer.
5. Add comment-based help and at least one usage example.
6. Document required PowerShell versions and modules.
7. Add safe handling for potentially destructive operations.
8. Use meaningful file names and clear variable names.

## Recommended script header

```powershell
<#
.SYNOPSIS
    Short description.

.DESCRIPTION
    Detailed description of what the script does.

.PARAMETER Example
    Description of the parameter.

.EXAMPLE
    .\Example-Script.ps1 -Example Value

.NOTES
    Author: Hubert Inderwildi
    Version: 1.0.0
    Requires: PowerShell 7.x (adapt as required)
#>
```

## Naming

Use approved PowerShell verbs where practical and descriptive names such as:

```text
Get-ADSecurityReport.ps1
Test-DnsConfiguration.ps1
Export-M365Inventory.ps1
Set-WindowsSecurityBaseline.ps1
```

## Pull requests

Keep changes focused. Explain what changed, how it was tested and whether the change can modify production systems.
