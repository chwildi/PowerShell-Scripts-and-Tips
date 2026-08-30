# PowerShell Script Templates

This folder contains the standard templates for new scripts published in **PowerShell Scripts & Tips**.

## Mandatory file pair

Every productive PowerShell script in this repository must have a companion test script in the same folder.

Naming standard:

```text
Get-Something.ps1
Get-Something-TEST.ps1
README.md
```

The `-TEST.ps1` suffix is mandatory for the companion test script.

## Templates

### `PowerShell-Script-Template.ps1`

Reusable starting point for productive scripts with:

- PowerShell comment-based help
- `.SYNOPSIS` and `.DESCRIPTION`
- parameter documentation
- multiple `.EXAMPLE` blocks
- `.INPUTS`, `.OUTPUTS`, `.NOTES` and `.LINK`
- `[CmdletBinding(SupportsShouldProcess = $true)]`
- `-WhatIf` and `-Confirm` support for modifying operations
- strict mode and controlled error handling
- timestamped logging helper
- main execution block with `try/catch/finally`
- security and publishing reminders

### `PowerShell-Script-TEST-Template.ps1`

Starting point for the mandatory companion test script. It contains generic checks for:

- script readability
- PowerShell parser / syntax errors
- required comment-based help sections
- obvious embedded secret patterns
- unsafe modifying cmdlets without `SupportsShouldProcess`
- optional PSScriptAnalyzer execution
- PASS / WARN / FAIL / SKIP result reporting
- non-zero exit code when a test fails

Every test script must then be extended with tests specific to the productive script.

## Test expectations

Depending on the script, test as many of the following as reasonably possible:

1. PowerShell syntax and parser errors.
2. Required PowerShell version.
3. Required modules and dependencies.
4. Configuration block values.
5. Mandatory and optional parameters.
6. Parameter validation and invalid input.
7. Comment-based help completeness.
8. Expected functions and commands.
9. Expected output properties and data types.
10. Empty-result behaviour.
11. Error handling and unavailable dependencies.
12. Export paths and generated files.
13. CSV, JSON, XML or TXT exports when supported.
14. `-WhatIf` / `ShouldProcess` behaviour for modifying scripts.
15. Obvious secrets or confidential values in source code.
16. PSScriptAnalyzer warnings/errors when available.
17. Script-specific functional checks that can be performed safely.

Tests must avoid destructive production changes. Where a real infrastructure dependency is required, the test script should clearly distinguish prerequisites from actual failures.

## How to create a new script

1. Copy `PowerShell-Script-Template.ps1` into the correct folder under `Scripts/`.
2. Rename it using a clear `Verb-Noun.ps1` name where practical.
3. Copy `PowerShell-Script-TEST-Template.ps1` into the same folder.
4. Rename the test file to `<ProductiveScriptName>-TEST.ps1`.
5. Create or update the folder's `README.md` with purpose, prerequisites, configuration, examples, output, tests and security notes.
6. Replace all template placeholders.
7. Remove parameters and sections that are not required.
8. Never insert passwords, API keys, tokens, private keys or real customer information.
9. Test in a lab or non-production environment.
10. Run the companion `-TEST.ps1` script.
11. Run PSScriptAnalyzer where available.
12. Perform a final security/privacy review before committing to the public repository.

## Example

```powershell
.\Get-Something-TEST.ps1 -ScriptPath .\Get-Something.ps1 -RunPSScriptAnalyzer
```

A productive script is considered complete only when its companion `-TEST.ps1` and documentation are present.
