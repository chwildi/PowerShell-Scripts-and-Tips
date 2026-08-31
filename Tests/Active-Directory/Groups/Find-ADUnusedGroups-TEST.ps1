#requires -Version 7.0
<#+
.SYNOPSIS
    Testskript fuer Find-ADUnusedGroups.ps1 Version 1.0.0.1.
.DESCRIPTION
    Fuehrt statische, Sicherheits-, Modul- und optional PSScriptAnalyzer-Tests aus.
    Es werden keine AD-Objekte geaendert.
#>
[CmdletBinding()]
param(
    [string]$ScriptPath = (Join-Path $PSScriptRoot '..\..\..\Scripts\Active-Directory\Groups\Find-ADUnusedGroups.ps1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$failures = [System.Collections.Generic.List[string]]::new()
$passes = [System.Collections.Generic.List[string]]::new()

function Add-TestResult {
    param([string]$Name,[bool]$Passed,[string]$Detail='')
    if ($Passed) { $passes.Add($Name); Write-Host "[PASS] $Name $Detail" }
    else { $failures.Add("$Name $Detail"); Write-Host "[FAIL] $Name $Detail" }
}

if (-not (Test-Path -LiteralPath $ScriptPath)) { throw "Skript nicht gefunden: $ScriptPath" }
$content = Get-Content -LiteralPath $ScriptPath -Raw

$tokens = $null; $errors = $null
[System.Management.Automation.Language.Parser]::ParseFile($ScriptPath,[ref]$tokens,[ref]$errors) | Out-Null
Add-TestResult 'PowerShell-Syntax' ($errors.Count -eq 0) (($errors | ForEach-Object Message) -join ' | ')

Add-TestResult 'PowerShell-7-Requirement' ($content -match '#requires\s+-Version\s+7')
Add-TestResult 'Configuration-Block-vorhanden' ($content -match 'CONFIGURATION BLOCK')
Add-TestResult 'CmdletBinding-vorhanden' ($content -match '\[CmdletBinding\(\)\]')
Add-TestResult 'Parameterlos-moeglich' (-not ($content -match 'Parameter\(Mandatory\s*=\s*\$true'))
Add-TestResult 'Keine-Remove-ADGroup-Verwendung' (-not ($content -match '\bRemove-ADGroup\b'))
Add-TestResult 'Keine-Set-ADGroup-Verwendung' (-not ($content -match '\bSet-ADGroup\b'))
Add-TestResult 'Keine-New-ADGroup-Verwendung' (-not ($content -match '\bNew-ADGroup\b'))
Add-TestResult 'Keine-Write-AD-Aktion' (-not ($content -match '\b(Add|Remove)-ADGroupMember\b'))
Add-TestResult 'Export-CSV-vorhanden' ($content -match 'Export-Csv')
Add-TestResult 'Logging-vorhanden' ($content -match 'function Write-Log')
Add-TestResult 'Transcript-vorhanden' ($content -match 'Start-Transcript')
Add-TestResult 'LAPS-Pruefung-vorhanden' ($content -match 'Find-LapsADExtendedRights')
Add-TestResult 'AD-Delegations-Pruefung-vorhanden' ($content -match 'Get-ADDelegationReferences')
Add-TestResult 'GPO-Pruefung-vorhanden' ($content -match 'Get-GpoReferences')
Add-TestResult 'SID-Ausgabe-vorhanden' ($content -match 'SID\s+=')
Add-TestResult 'DoNotDelete-Schutzfeld' ($content -match 'DoNotDelete')

$adModule = Get-Module -ListAvailable ActiveDirectory | Select-Object -First 1
Add-TestResult 'ActiveDirectory-Modul-verfuegbar' ($null -ne $adModule) $(if ($adModule) { "Version $($adModule.Version)" } else { 'Nicht installiert; Laufzeittest nicht moeglich.' })

if (Get-Module -ListAvailable PSScriptAnalyzer | Select-Object -First 1) {
    Import-Module PSScriptAnalyzer
    $analysis = @(Invoke-ScriptAnalyzer -Path $ScriptPath -Severity Warning,Error)
    Add-TestResult 'PSScriptAnalyzer-WarningError-frei' ($analysis.Count -eq 0) (($analysis | ForEach-Object { "$($_.RuleName): $($_.Message)" }) -join ' | ')
} else {
    Write-Host '[INFO] PSScriptAnalyzer ist nicht installiert. Test wird uebersprungen.'
}

Write-Host ''
Write-Host "Bestanden: $($passes.Count)"
Write-Host "Fehlgeschlagen: $($failures.Count)"
if ($failures.Count -gt 0) {
    Write-Host 'Fehler:'
    $failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}
Write-Host '[OK] Alle ausgefuehrten Tests bestanden.'
exit 0
