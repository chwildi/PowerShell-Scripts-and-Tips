#requires -Version 7.0
<#
.SYNOPSIS
    Standard companion test script template for a PowerShell script.
.DESCRIPTION
    Copy and adapt this file alongside each productive script. Generic tests alone are not sufficient.
.NOTES
    Author: Hubert Inderwildi
    Repository: PowerShell-Scripts-and-Tips
    Version: 1.1.0
    License: MIT
#>
[CmdletBinding()]
param(
    [Parameter()][ValidateScript({Test-Path -LiteralPath $_ -PathType Leaf})][string]$ScriptPath=(Join-Path $PSScriptRoot '..\Scripts\Example.ps1'),
    [Parameter()][switch]$RunPSScriptAnalyzer
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Results=[System.Collections.Generic.List[object]]::new()
function Add-TestResult{param([Parameter(Mandatory)][string]$Test,[Parameter(Mandatory)][ValidateSet('PASS','WARN','FAIL','SKIP')][string]$Status,[Parameter(Mandatory)][string]$Details);$Results.Add([pscustomobject]@{Test=$Test;Status=$Status;Details=$Details})}
function Invoke-TestCase{param([Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][scriptblock]$Test);try{$detail=& $Test;Add-TestResult -Test $Name -Status PASS -Details ([string]$detail)}catch{Add-TestResult -Test $Name -Status FAIL -Details $_.Exception.Message}}
if(-not(Test-Path -LiteralPath $ScriptPath -PathType Leaf)){Add-TestResult -Test 'Script file' -Status SKIP -Details "Template default target does not exist: $ScriptPath";$Results|Format-Table -AutoSize;Write-Information -MessageData 'Template test skipped until ScriptPath is adapted.' -InformationAction Continue;exit 0}
$ResolvedScriptPath=(Resolve-Path -LiteralPath $ScriptPath).Path
$ScriptContent=Get-Content -LiteralPath $ResolvedScriptPath -Raw -Encoding utf8
Invoke-TestCase -Name 'Script file readable' -Test {if([string]::IsNullOrWhiteSpace($ScriptContent)){throw 'Script is empty.'};"Readable: $ResolvedScriptPath"}
Invoke-TestCase -Name 'PowerShell syntax' -Test {$tokens=$null;$errors=$null;[void][System.Management.Automation.Language.Parser]::ParseFile($ResolvedScriptPath,[ref]$tokens,[ref]$errors);if($errors.Count -gt 0){throw(($errors|ForEach-Object Message)-join ' | ')};'No parser errors detected.'}
Invoke-TestCase -Name 'Comment-based help' -Test {foreach($section in '.SYNOPSIS','.DESCRIPTION','.NOTES'){if($ScriptContent -notmatch [regex]::Escape($section)){throw "Missing help section: $section"}};'Required help sections found.'}
Invoke-TestCase -Name 'No obvious hard-coded secrets' -Test {$patterns=@('(?i)password\s*=\s*["''][^"'']+["'']','(?i)clientsecret\s*=\s*["''][^"'']+["'']','(?i)apikey\s*=\s*["''][^"'']+["'']','(?i)access[_-]?token\s*=\s*["''][^"'']+["'']','-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----');foreach($pattern in $patterns){if($ScriptContent -match $pattern){throw "Potential secret pattern detected: $pattern"}};'No obvious embedded secret pattern detected.'}
Invoke-TestCase -Name 'Supports safe preview when modifying' -Test {if($ScriptContent -match '(?i)\b(Set|New|Remove|Disable|Enable|Add|Clear|Move|Rename)-[A-Za-z0-9]+' -and $ScriptContent -notmatch 'SupportsShouldProcess'){throw 'Potential modifying cmdlets found but SupportsShouldProcess was not detected.'};'No unsafe modifying pattern detected by generic check.'}
if($RunPSScriptAnalyzer){if(Get-Module -ListAvailable PSScriptAnalyzer){$issues=Invoke-ScriptAnalyzer -Path $ResolvedScriptPath -Severity Warning,Error;if($issues){Add-TestResult -Test PSScriptAnalyzer -Status WARN -Details (($issues|ForEach-Object{"[$($_.Severity)] $($_.RuleName): $($_.Message)"})-join ' | ')}else{Add-TestResult -Test PSScriptAnalyzer -Status PASS -Details 'No warnings or errors.'}}else{Add-TestResult -Test PSScriptAnalyzer -Status SKIP -Details 'PSScriptAnalyzer is not installed.'}}
$Results|Format-Table -AutoSize
$failed=@($Results|Where-Object Status -eq FAIL);$warnings=@($Results|Where-Object Status -eq WARN)
Write-Information -MessageData "Tests: $($Results.Count) | Failed: $($failed.Count) | Warnings: $($warnings.Count)" -InformationAction Continue
if($failed.Count -gt 0){exit 1};exit 0
