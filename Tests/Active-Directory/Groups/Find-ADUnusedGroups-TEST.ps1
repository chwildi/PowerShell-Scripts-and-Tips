#requires -Version 7.0
<#+
.SYNOPSIS
    Testskript fuer Find-ADUnusedGroups.ps1 Version 1.0.0.1.
.DESCRIPTION
    Fuehrt statische, Sicherheits- und PSScriptAnalyzer-Tests aus.
    Infrastrukturabhaengige AD-Laufzeittests werden nur als Hinweis bewertet,
    wenn das ActiveDirectory-Modul auf dem Testsystem nicht vorhanden ist.
#>
[CmdletBinding()]
param(
    [string]$ScriptPath = (Join-Path $PSScriptRoot '..\..\..\Scripts\Active-Directory\Groups\Find-ADUnusedGroups.ps1'),
    [switch]$RequirePSScriptAnalyzer
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$failures = [System.Collections.Generic.List[string]]::new()
$passes = [System.Collections.Generic.List[string]]::new()

function Add-TestResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][bool]$Passed,
        [string]$Detail = ''
    )

    if ($Passed) {
        $passes.Add($Name)
        Write-Output "[PASS] $Name $Detail"
    }
    else {
        $failures.Add("$Name $Detail")
        Write-Output "[FAIL] $Name $Detail"
    }
}

if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
    throw "Skript nicht gefunden: $ScriptPath"
}

$content = Get-Content -LiteralPath $ScriptPath -Raw
$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$tokens, [ref]$parseErrors)
Add-TestResult -Name 'PowerShell-Syntax' -Passed ($parseErrors.Count -eq 0) -Detail (($parseErrors | ForEach-Object Message) -join ' | ')

Add-TestResult -Name 'PowerShell-7-Requirement' -Passed ($content -match '#requires\s+-Version\s+7')
Add-TestResult -Name 'Configuration-Block-vorhanden' -Passed ($content -match 'CONFIGURATION BLOCK')
Add-TestResult -Name 'CmdletBinding-vorhanden' -Passed ($content -match '\[CmdletBinding\(\)\]')
Add-TestResult -Name 'Parameterlos-moeglich' -Passed (-not ($content -match 'Parameter\(Mandatory\s*=\s*\$true'))
Add-TestResult -Name 'Keine-Remove-ADGroup-Verwendung' -Passed (-not ($content -match '\bRemove-ADGroup\b'))
Add-TestResult -Name 'Keine-Set-ADGroup-Verwendung' -Passed (-not ($content -match '\bSet-ADGroup\b'))
Add-TestResult -Name 'Keine-New-ADGroup-Verwendung' -Passed (-not ($content -match '\bNew-ADGroup\b'))
Add-TestResult -Name 'Keine-Write-AD-Aktion' -Passed (-not ($content -match '\b(Add|Remove)-ADGroupMember\b'))
Add-TestResult -Name 'Export-CSV-vorhanden' -Passed ($content -match 'Export-Csv')
Add-TestResult -Name 'Logging-vorhanden' -Passed ($content -match 'function Write-AnalysisLog')
Add-TestResult -Name 'Transcript-vorhanden' -Passed ($content -match 'Start-Transcript')
Add-TestResult -Name 'LAPS-Pruefung-vorhanden' -Passed ($content -match 'Find-LapsADExtendedRights')
Add-TestResult -Name 'AD-Delegations-Pruefung-vorhanden' -Passed ($content -match 'Get-ADDelegationReference')
Add-TestResult -Name 'GPO-Pruefung-vorhanden' -Passed ($content -match 'Get-GpoReference')
Add-TestResult -Name 'SID-Ausgabe-vorhanden' -Passed ($content -match 'SID\s+=')
Add-TestResult -Name 'DoNotDelete-Schutzfeld' -Passed ($content -match 'DoNotDelete')
Add-TestResult -Name 'Keine-automatische-Loeschung' -Passed (-not ($content -match '\b(Remove-ADObject|Remove-Item\s+AD:|dsrm\.exe)\b'))

$adModule = Get-Module -ListAvailable -Name ActiveDirectory | Select-Object -First 1
if ($adModule) {
    Write-Output "[INFO] ActiveDirectory-Modul verfuegbar: Version $($adModule.Version). Live-AD-Tests sind separat in einer autorisierten AD-Umgebung durchzufuehren."
}
else {
    Write-Output '[INFO] ActiveDirectory-Modul auf diesem Runner nicht vorhanden. Infrastruktur-Laufzeittest wird nicht als Fehler gewertet.'
}

$analyzer = Get-Module -ListAvailable -Name PSScriptAnalyzer | Select-Object -First 1
if ($analyzer) {
    Import-Module PSScriptAnalyzer -Force
    $analysis = @(Invoke-ScriptAnalyzer -Path $ScriptPath -Severity Warning,Error)
    Add-TestResult -Name 'PSScriptAnalyzer-WarningError-frei' -Passed ($analysis.Count -eq 0) -Detail (($analysis | ForEach-Object { "$($_.RuleName): $($_.Message)" }) -join ' | ')
}
elseif ($RequirePSScriptAnalyzer) {
    Add-TestResult -Name 'PSScriptAnalyzer-verfuegbar' -Passed $false -Detail 'PSScriptAnalyzer wurde vom Aufrufer verlangt, ist aber nicht installiert.'
}
else {
    Write-Output '[INFO] PSScriptAnalyzer ist nicht installiert. Analyzer-Test wird uebersprungen.'
}

Write-Output ''
Write-Output "Bestanden: $($passes.Count)"
Write-Output "Fehlgeschlagen: $($failures.Count)"

if ($failures.Count -gt 0) {
    Write-Output 'Fehler:'
    foreach ($failure in $failures) {
        Write-Output " - $failure"
    }
    exit 1
}

Write-Output '[OK] Alle ausgefuehrten Tests bestanden.'
exit 0
