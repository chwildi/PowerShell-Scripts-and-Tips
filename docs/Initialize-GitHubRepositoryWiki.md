# Initialize-GitHubRepositoryWiki

`Initialize-GitHubRepositoryWiki.ps1` builds and synchronizes a GitHub repository Wiki from Markdown files stored in the main repository.

## Safety model

The script defaults to `Audit`. A parameterless run does not clone, commit, delete or push anything. Remote publication additionally requires `-Push`. Modifying operations support `-WhatIf` through `ShouldProcess`.

## Prerequisites

- PowerShell 7+
- Git command line client in `PATH`
- Local clone of the source repository
- GitHub Wiki enabled for the target repository
- At least one Wiki page created once through GitHub before the Wiki Git repository can be cloned
- Git authentication configured for push operations

## Default source mapping

| Wiki page | Repository source |
|---|---|
| Home.md | docs/Wiki-Home.md |
| Script-Catalog.md | SCRIPT-CATALOG.md |
| Changelog.md | CHANGELOG.md |
| Compatibility-Matrix.md | docs/Compatibility-Matrix.md |
| Migration-Migriere-WindowsBenutzer.md | docs/Migriere-WindowsBenutzer.md |

The script also generates `_Sidebar.md` and `_Footer.md`.

## Usage

Safe audit:

```powershell
.\Scripts\Utilities\Initialize-GitHubRepositoryWiki.ps1
```

Preview initialization:

```powershell
.\Scripts\Utilities\Initialize-GitHubRepositoryWiki.ps1 -Mode Initialize -WhatIf
```

Initialize and publish:

```powershell
.\Scripts\Utilities\Initialize-GitHubRepositoryWiki.ps1 -Mode Initialize -Push
```

Synchronize later changes:

```powershell
.\Scripts\Utilities\Initialize-GitHubRepositoryWiki.ps1 -Mode Sync -Push
```

Use another repository:

```powershell
.\Scripts\Utilities\Initialize-GitHubRepositoryWiki.ps1 -Mode Sync -Repository 'owner/repository' -RepositoryRoot 'C:\Code\repository' -Push
```

## Authentication

The script intentionally stores no token or password. Authentication is delegated to Git/Git Credential Manager or another Git authentication method configured on the workstation.

## Failure when the Wiki does not yet exist

If `git clone https://github.com/<owner>/<repository>.wiki.git` fails for a repository whose Wiki has never been initialized, open the repository on GitHub, enable the Wiki if necessary and create its first page once. Then rerun the script.

## Testing

Matching test script:

```powershell
.\Tests\Utilities\Initialize-GitHubRepositoryWiki-TEST.ps1 -RequirePSScriptAnalyzer
```

The repository GitHub Actions workflow also parses the script, runs PSScriptAnalyzer and executes matching test scripts.

## Module recommendation

This script is a good future module candidate. Suggested public functions are `Get-GitHubWikiUrl`, `Get-WikiSourceStatus` and `Invoke-GitHubRepositoryWiki`. Helper functions for navigation generation, working-copy management, source copying and Git publication should remain private module functions.
