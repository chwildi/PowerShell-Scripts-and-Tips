# PowerShell Script Template

This folder contains the standard template for new scripts published in **PowerShell Scripts & Tips**.

## File

`PowerShell-Script-Template.ps1` provides a reusable starting point with:

- PowerShell comment-based help
- `.SYNOPSIS` and `.DESCRIPTION`
- Parameter documentation
- Multiple `.EXAMPLE` blocks
- `.INPUTS`, `.OUTPUTS`, `.NOTES` and `.LINK`
- `[CmdletBinding(SupportsShouldProcess = $true)]`
- `-WhatIf` and `-Confirm` support for modifying operations
- strict mode and controlled error handling
- timestamped logging helper
- a main execution block with `try/catch/finally`
- security and publishing reminders

## How to use

1. Copy `PowerShell-Script-Template.ps1` into the correct folder under `Scripts/`.
2. Rename the file using a clear `Verb-Noun.ps1` name where practical.
3. Replace every placeholder in angle brackets, for example `<Short description>`.
4. Remove parameters and sections that your script does not need.
5. Document all prerequisites and required PowerShell modules.
6. Never insert passwords, API keys, tokens, private keys or real customer information.
7. Test the script in a lab or non-production environment.
8. Test modifying commands with `-WhatIf` before real execution.
9. Run PSScriptAnalyzer where available.
10. Perform a final security/privacy review before committing to the public repository.

## Example

```powershell
.\PowerShell-Script-Template.ps1 -Target 'Server01' -WhatIf -Verbose
```

The template is intentionally generic. A published script should contain only the parameters and functions it actually requires.
