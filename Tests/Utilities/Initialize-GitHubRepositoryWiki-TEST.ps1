#requires -Version 7.0
<#
.SYNOPSIS
    Static quality tests for Initialize-GitHubRepositoryWiki.ps1.
.NOTES
    Version: 1.0.2.0
    License: MIT
#>
[CmdletBinding()]
param(
    [string]$ScriptPath=(Join-Path $PSScriptRoot '..\..\Scripts\Utilities\Initialize-GitHubRepositoryWiki.ps1'),
    [switch]$RequirePSScriptAnalyzer
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# ============================================================================
# CONFIGURATION BLOCK
# ============================================================================
$Configuration=[ordered]@{ScriptPath=$ScriptPath;RequirePSScriptAnalyzer=[bool]$RequirePSScriptAnalyzer;RequiredVersion='1.0.2.0'}
$Results=[System.Collections.Generic.List[object]]::new()
function Add-WikiTestResult{[CmdletBinding()]param([Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][bool]$Passed,[Parameter(Mandatory)][string]$Detail);$Results.Add([pscustomobject]@{Test=$Name;Passed=$Passed;Detail=$Detail})}
if(-not(Test-Path -LiteralPath $Configuration.ScriptPath -PathType Leaf)){throw "Script not found: $($Configuration.ScriptPath)"}
$content=Get-Content -LiteralPath $Configuration.ScriptPath -Raw
$tokens=$null;$errors=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($Configuration.ScriptPath,[ref]$tokens,[ref]$errors)
Add-WikiTestResult 'PowerShell syntax' ($errors.Count -eq 0) $(if($errors.Count){($errors.Message -join '; ')}else{'No parser errors'})
Add-WikiTestResult 'PowerShell 7 requirement' ($content -match '#requires\s+-Version\s+7\.0') 'Expected PowerShell 7 requirement'
Add-WikiTestResult 'Configuration block' ($content -match '(?i)CONFIGURATION BLOCK') 'Expected safe configuration block'
Add-WikiTestResult 'Safe Audit default' ($content -match "Mode='Audit'") 'No-parameter execution must be read-only'
Add-WikiTestResult 'ShouldProcess support' ($content -match 'SupportsShouldProcess\s*=\s*\$true') 'Modifying actions require WhatIf support'
Add-WikiTestResult 'Explicit push opt-in' (($content -match 'Push=\$false') -and ($content -match '\[switch\]\$Push')) 'Remote push must be opt-in'
Add-WikiTestResult 'Wiki URL construction' ($content -match '\.wiki\.git') 'Expected GitHub wiki Git URL'
Add-WikiTestResult 'Sidebar generation' ($content -match '_Sidebar\.md') 'Expected generated navigation'
Add-WikiTestResult 'Footer generation' ($content -match '_Footer\.md') 'Expected generated footer'
Add-WikiTestResult 'Git command output isolated' (($content -match '\$null=& git add') -and ($content -match '\$null=& git commit') -and ($content -match '\$null=& git push')) 'Native Git output must not pollute the structured result pipeline'
Add-WikiTestResult 'Structured publish result' (($content -match 'Changed=\$true') -and ($content -match 'Committed=\$committed') -and ($content -match 'Pushed=\$pushed')) 'Publish function must return a stable result object'
Add-WikiTestResult 'Version marker' ($content -match [regex]::Escape($Configuration.RequiredVersion)) "Expected version $($Configuration.RequiredVersion)"
Add-WikiTestResult 'No obvious secrets' (-not($content -match '(?i)(password\s*=|clientsecret\s*=|api[_-]?key\s*=|token\s*=\s*["''][^"'']+)')) 'Basic secret scan'
$analyzer=Get-Module -ListAvailable PSScriptAnalyzer|Sort-Object Version -Descending|Select-Object -First 1
if($analyzer){Import-Module PSScriptAnalyzer -ErrorAction Stop;$issues=@(Invoke-ScriptAnalyzer -Path $Configuration.ScriptPath -Severity Error,Warning);Add-WikiTestResult 'PSScriptAnalyzer' ($issues.Count -eq 0) $(if($issues.Count){($issues|ForEach-Object{"[$($_.RuleName)] line $($_.Line): $($_.Message)"}) -join ' | '}else{'No Error/Warning findings'})}else{Add-WikiTestResult 'PSScriptAnalyzer available' (-not $Configuration.RequirePSScriptAnalyzer) 'Install PSScriptAnalyzer for publication validation'}
$Results|Format-Table -AutoSize
$failed=@($Results|Where-Object{-not $_.Passed})
if($failed.Count){throw "$($failed.Count) test(s) failed: $($failed.Test -join ', ')"}
Write-Information -MessageData 'All tests passed.' -InformationAction Continue
