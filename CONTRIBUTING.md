# Contributing

Contributions, corrections and improvements are welcome.

## Mandatory script package

Every productive PowerShell script must be published together with:

```text
Verb-Noun.ps1
Verb-Noun-TEST.ps1
README.md
```

The companion test script must use the `-TEST.ps1` suffix and should test as many relevant aspects of the productive script as safely possible.

## Before publishing

1. Remove all customer-specific and confidential information.
2. Never commit passwords, tokens, API keys or private certificates.
3. Test the script in an appropriate non-production environment.
4. Run PowerShell syntax validation and, where possible, PSScriptAnalyzer.
5. Add comment-based help and usage examples.
6. Document required PowerShell versions and modules.
7. Add safe handling for potentially destructive operations.
8. Use meaningful file names and clear variable names.
9. Create the matching `-TEST.ps1` companion script.
10. Test configuration, parameters, expected output, exports, error handling and dependencies where relevant.
11. Document how to execute the tests in the accompanying README.

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
Get-ADSecurityReport-TEST.ps1

Export-M365Inventory.ps1
Export-M365Inventory-TEST.ps1
```

## Tests

Generic tests are useful but are not enough. The companion test script must be adapted to the productive script. Tests should include syntax, dependencies, configuration, parameters, output schema, exports, error cases, safe execution and PSScriptAnalyzer where applicable.

Tests must not intentionally make destructive changes to a production environment.

## Pull requests

Keep changes focused. Explain what changed, how it was tested and whether the change can modify production systems.
