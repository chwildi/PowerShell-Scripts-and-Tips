#requires -Version 7.0
<#
.SYNOPSIS
    Sicherheits- und Strukturtests fuer Migriere-WindowsBenutzer.ps1.

.DESCRIPTION
    Prueft das Skript ohne einen Export oder Import auszufuehren. Der Test verwendet
    den PowerShell-Parser und kontrolliert die projektspezifischen GitHub-Richtlinien,
    Cloud-Ausschluesse sowie die Unterstuetzung lokaler Browser-Lesezeichen.

.NOTES
    Author: Hubert Josef Inderwildi
    License: MIT
    Version: 2.1.1
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ScriptPath = (Join-Path $PSScriptRoot 'Migriere-WindowsBenutzer.ps1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$failures = [System.Collections.Generic.List[string]]::new()
$passes = [System.Collections.Generic.List[string]]::new()

function Test-Requirement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [bool]$Condition,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    if ($Condition) {
        $passes.Add($Name)
        Write-Host "[OK] $Name" -ForegroundColor Green
    }
    else {
        $failures.Add($Name)
        Write-Host "[FEHLER] $Name" -ForegroundColor Red
    }
}

if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
    throw "Zu testendes Skript nicht gefunden: $ScriptPath"
}

$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $ScriptPath,
    [ref]$tokens,
    [ref]$parseErrors
)
$content = Get-Content -LiteralPath $ScriptPath -Raw -ErrorAction Stop

Test-Requirement -Condition ($parseErrors.Count -eq 0) -Name 'PowerShell-Syntax ist fehlerfrei'
if ($parseErrors.Count -gt 0) {
    $parseErrors | ForEach-Object { Write-Host "  Zeile $($_.Extent.StartLineNumber): $($_.Message)" -ForegroundColor Red }
}

$functionNames = @(
    $ast.FindAll(
        { param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] },
        $true
    ).Name
)

foreach ($requiredFunction in @(
    'Initialize-MigrationLog',
    'Write-MigrationLog',
    'Invoke-SafeRobocopy',
    'Get-CloudStorageRoot',
    'Test-IsCloudBackedPath',
    'Export-BrowserBookmarks',
    'Import-BrowserBookmarks',
    'Test-UserMigrationPrerequisite'
)) {
    Test-Requirement -Condition ($requiredFunction -in $functionNames) -Name "Funktion vorhanden: $requiredFunction"
}

Test-Requirement -Condition ($content -match "Mode\s*=\s*'Audit'") -Name 'Parameterloser Standardmodus ist Audit'
Test-Requirement -Condition ($content -match 'BackupRoot\s*=\s*Join-Path\s+\$PSScriptRoot') -Name 'Standard-Sicherungsziel liegt neben dem Skript'
Test-Requirement -Condition ($content -notmatch "BackupRoot\s*=.*GetFolderPath\('MyDocuments'\)") -Name 'OneDrive-Dokumente werden nicht als Standardziel verwendet'
Test-Requirement -Condition ($content -match 'EnableLogging\s*=\s*\$true') -Name 'Logging ist standardmaessig aktiviert'
Test-Requirement -Condition ($content -match "LogDirectoryName\s*=\s*'Logs'") -Name 'Log-Unterverzeichnis entspricht dem Standard'
Test-Requirement -Condition ($content -match 'ExcludeCloudBackedData\s*=\s*\$true') -Name 'Cloud-Daten sind standardmaessig ausgeschlossen'
Test-Requirement -Condition ($content -match 'ExcludeOfficeCloudData\s*=\s*\$true') -Name 'Microsoft-365-/Office-Cloud-Daten sind ausgeschlossen'
Test-Requirement -Condition ($content -match 'OneDriveCommercial') -Name 'OneDrive for Business wird erkannt'
Test-Requirement -Condition ($content -match 'SyncEngines\\Providers\\OneDrive') -Name 'SharePoint-/OneDrive-Sync-Roots werden aus der Registry erkannt'
Test-Requirement -Condition ($content -match 'Dropbox') -Name 'Dropbox wird erkannt'
Test-Requirement -Condition ($content -match 'Google Drive') -Name 'Google Drive wird erkannt'
Test-Requirement -Condition ($content -match 'iCloudDrive') -Name 'iCloud Drive wird erkannt'
Test-Requirement -Condition ($content -match "'Microsoft Edge'.*'Chromium'") -Name 'Edge-Lesezeichen werden unterstuetzt'
Test-Requirement -Condition ($content -match "'Google Chrome'.*'Chromium'") -Name 'Chrome-Lesezeichen werden unterstuetzt'
Test-Requirement -Condition ($content -match "'Brave'.*'Chromium'") -Name 'Brave-Lesezeichen werden unterstuetzt'
Test-Requirement -Condition ($content -match "'Vivaldi'.*'Chromium'") -Name 'Vivaldi-Lesezeichen werden unterstuetzt'
Test-Requirement -Condition ($content -match "'Opera Stable'.*'Opera'") -Name 'Opera-Lesezeichen werden unterstuetzt'
Test-Requirement -Condition ($content -match "'Opera GX'.*'Opera'") -Name 'Opera-GX-Lesezeichen werden unterstuetzt'
Test-Requirement -Condition ($content -match "'Mozilla Firefox'.*'Firefox'") -Name 'Firefox-Lesezeichen werden unterstuetzt'
Test-Requirement -Condition ($content -match "@\('places.sqlite', 'favicons.sqlite'\)") -Name 'Firefox-Favoriten und Symbole werden gesichert'
Test-Requirement -Condition ($content -notmatch "Microsoft\\Signatures.*Copy-OptionalMigrationItem") -Name 'Office-Cloud-Einstellungen werden nicht exportiert'
Test-Requirement -Condition ($content -match "ExcludedFilePatterns\s*=\s*@\('\*\.ost'") -Name 'Outlook-OST-Dateien sind ausgeschlossen'
Test-Requirement -Condition ($content -match "CmdletBinding\(SupportsShouldProcess") -Name 'ShouldProcess/WhatIf-Schutz ist vorhanden'
Test-Requirement -Condition ($content -match 'Set-StrictMode -Version Latest') -Name 'StrictMode ist aktiviert'

Write-Host ''
Write-Host ("Testergebnis: {0} erfolgreich, {1} fehlgeschlagen." -f $passes.Count, $failures.Count)

if ($failures.Count -gt 0) {
    Write-Host ('Fehlgeschlagene Tests: ' + ($failures -join '; ')) -ForegroundColor Red
    exit 1
}

exit 0
