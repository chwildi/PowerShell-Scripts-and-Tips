#requires -Version 7.0
<#
.SYNOPSIS
    Static and quality tests for Migriere-WindowsBenutzer.ps1.

.DESCRIPTION
    Performs safe tests without running Export or Import. Uses the PowerShell AST parser,
    checks required project conventions, and runs PSScriptAnalyzer when installed.

.NOTES
    Version: 2.0.0.0
    License: MIT
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ScriptPath = (Join-Path $PSScriptRoot '..\..\Scripts\Migration\Migriere-WindowsBenutzer.ps1'),

    [Parameter()]
    [switch]$RequirePSScriptAnalyzer
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ============================================================================
# CONFIGURATION BLOCK
# ============================================================================
$Configuration = [ordered]@{
    ScriptPath              = $ScriptPath
    RequirePSScriptAnalyzer = [bool]$RequirePSScriptAnalyzer
    RequiredVersion         = '7.0'
    RequiredScriptVersion   = '2.0.0.0'
}

$results = [System.Collections.Generic.List[object]]::new()

function Add-TestResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][bool]$Passed,
        [Parameter(Mandatory)][string]$Detail
    )
    $results.Add([pscustomobject]@{ Test = $Name; Passed = $Passed; Detail = $Detail })
}

if (-not (Test-Path -LiteralPath $Configuration.ScriptPath -PathType Leaf)) {
    throw "Script not found: $($Configuration.ScriptPath)"
}

$content = Get-Content -LiteralPath $Configuration.ScriptPath -Raw
$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($Configuration.ScriptPath, [ref]$tokens, [ref]$parseErrors)
Add-TestResult -Name 'PowerShell syntax' -Passed ($parseErrors.Count -eq 0) -Detail $(if ($parseErrors.Count -eq 0) { 'No parser errors' } else { ($parseErrors.Message -join '; ') })

Add-TestResult -Name 'Requires PowerShell 7' -Passed ($content -match '#requires\s+-Version\s+7\.0') -Detail 'Expected #requires -Version 7.0'
Add-TestResult -Name 'Configuration block present' -Passed ($content -match '(?i)CONFIGURATION BLOCK') -Detail 'Customer configurable defaults must be near the beginning'
Add-TestResult -Name 'Safe no-parameter mode' -Passed ($content -match "Mode\s*=\s*'Audit'") -Detail 'No-parameter execution must not export or import data'
Add-TestResult -Name 'No mandatory top-level parameters' -Passed (-not ($content -match '\[Parameter\(Mandatory\s*=\s*\$true\)\]')) -Detail 'Top-level parameters should remain optional'
Add-TestResult -Name 'Supports ShouldProcess' -Passed ($content -match 'SupportsShouldProcess\s*=\s*\$true') -Detail 'State-changing operations need WhatIf/Confirm support'
Add-TestResult -Name 'MIT license marker' -Passed ($content -match '(?im)^\s*License:\s*MIT\s*$') -Detail 'Expected MIT license marker in header'
Add-TestResult -Name 'Expected version' -Passed ($content -match [regex]::Escape($Configuration.RequiredScriptVersion)) -Detail "Expected $($Configuration.RequiredScriptVersion)"
Add-TestResult -Name 'No obvious customer domain' -Passed (-not ($content -match '(?i)iqplus|corp\.iqplus|inderwildi\.org')) -Detail 'No customer-specific tenant/domain strings should be embedded'
Add-TestResult -Name 'No obvious secrets' -Passed (-not ($content -match '(?i)(password\s*=|passwd\s*=|clientsecret\s*=|api[_-]?key\s*=|token\s*=\s*["''][^"'']+)')) -Detail 'Basic secret-pattern scan'
Add-TestResult -Name 'Wi-Fi clear-text protected' -Passed (($content -match 'AllowClearTextWifiKeys') -and ($content -match 'key=clear')) -Detail 'Clear-text Wi-Fi export requires explicit opt-in'

$analyzer = Get-Module -ListAvailable -Name PSScriptAnalyzer | Sort-Object Version -Descending | Select-Object -First 1
if ($analyzer) {
    Import-Module PSScriptAnalyzer -ErrorAction Stop
    $issues = @(Invoke-ScriptAnalyzer -Path $Configuration.ScriptPath -Severity @('Error', 'Warning'))
    Add-TestResult -Name 'PSScriptAnalyzer' -Passed ($issues.Count -eq 0) -Detail $(if ($issues.Count -eq 0) { 'No Error/Warning findings' } else { ($issues | ForEach-Object { "[$($_.RuleName)] line $($_.Line): $($_.Message)" }) -join ' | ' })
}
else {
    Add-TestResult -Name 'PSScriptAnalyzer available' -Passed (-not $Configuration.RequirePSScriptAnalyzer) -Detail 'Install-Module PSScriptAnalyzer -Scope CurrentUser'
}

$results | Format-Table -AutoSize
$failed = @($results | Where-Object { -not $_.Passed })
if ($failed.Count -gt 0) {
    throw "$($failed.Count) test(s) failed: $($failed.Test -join ', ')"
}

Write-Host "`nAll tests passed." -ForegroundColor Green
