#requires -Version 7.0

<#
.SYNOPSIS
    Standard companion test script template for a PowerShell script.

.DESCRIPTION
    This template is intended to be copied and renamed alongside every
    productive PowerShell script in this repository.

    Naming standard:
      Productive script : Get-Something.ps1
      Test script       : Get-Something-TEST.ps1

    The test script should validate as many relevant aspects as possible
    without making unintended changes to production systems.

    Recommended test areas:
    - File and syntax validation
    - Required PowerShell version
    - Required modules
    - Parameter presence and validation
    - Comment-based help
    - Configuration block validation
    - Dependency checks
    - Safe execution / -WhatIf where supported
    - Expected output properties
    - Export path and file generation
    - Error handling
    - No embedded secrets or obvious environment-specific placeholders
    - PSScriptAnalyzer when available

.PARAMETER ScriptPath
    Path to the productive PowerShell script that should be tested.

.PARAMETER RunPSScriptAnalyzer
    Runs PSScriptAnalyzer when the module is installed.

.EXAMPLE
    .\Get-Something-TEST.ps1 -ScriptPath .\Get-Something.ps1

.EXAMPLE
    .\Get-Something-TEST.ps1 -ScriptPath .\Get-Something.ps1 -RunPSScriptAnalyzer

.NOTES
    Author      : Hubert Inderwildi
    Repository  : PowerShell-Scripts-and-Tips
    Version     : 1.0.0

    IMPORTANT:
    Adapt this test script to the productive script. Generic tests alone
    are not sufficient for publication.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$ScriptPath,

    [Parameter(Mandatory = $false)]
    [switch]$RunPSScriptAnalyzer
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Results = [System.Collections.Generic.List[object]]::new()

function Add-TestResult {
    param(
        [Parameter(Mandatory)] [string]$Test,
        [Parameter(Mandatory)] [ValidateSet('PASS','WARN','FAIL','SKIP')] [string]$Status,
        [Parameter(Mandatory)] [string]$Details
    )

    $Results.Add([pscustomobject]@{
        Test    = $Test
        Status  = $Status
        Details = $Details
    })
}

function Invoke-TestCase {
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [scriptblock]$Test
    )

    try {
        $detail = & $Test
        Add-TestResult -Test $Name -Status 'PASS' -Details ([string]$detail)
    }
    catch {
        Add-TestResult -Test $Name -Status 'FAIL' -Details $_.Exception.Message
    }
}

$ResolvedScriptPath = (Resolve-Path -LiteralPath $ScriptPath).Path
$ScriptContent = Get-Content -LiteralPath $ResolvedScriptPath -Raw -Encoding utf8

Invoke-TestCase -Name 'Script file readable' -Test {
    if ([string]::IsNullOrWhiteSpace($ScriptContent)) {
        throw 'Script is empty.'
    }
    "Readable: $ResolvedScriptPath"
}

Invoke-TestCase -Name 'PowerShell syntax' -Test {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $ResolvedScriptPath,
        [ref]$tokens,
        [ref]$errors
    )

    if ($errors.Count -gt 0) {
        throw (($errors | ForEach-Object Message) -join ' | ')
    }

    'No parser errors detected.'
}

Invoke-TestCase -Name 'Comment-based help' -Test {
    foreach ($section in '.SYNOPSIS', '.DESCRIPTION', '.EXAMPLE', '.NOTES') {
        if ($ScriptContent -notmatch [regex]::Escape($section)) {
            throw "Missing help section: $section"
        }
    }
    'Required help sections found.'
}

Invoke-TestCase -Name 'No obvious hard-coded secrets' -Test {
    $patterns = @(
        '(?i)password\s*=\s*["''][^"'']+["'']',
        '(?i)clientsecret\s*=\s*["''][^"'']+["'']',
        '(?i)apikey\s*=\s*["''][^"'']+["'']',
        '(?i)access[_-]?token\s*=\s*["''][^"'']+["'']',
        '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'
    )

    foreach ($pattern in $patterns) {
        if ($ScriptContent -match $pattern) {
            throw "Potential secret pattern detected: $pattern"
        }
    }

    'No obvious embedded secret pattern detected.'
}

Invoke-TestCase -Name 'Supports safe preview when modifying' -Test {
    if ($ScriptContent -match '(?i)\b(Set|New|Remove|Disable|Enable|Add|Clear|Move|Rename)-[A-Za-z0-9]+' -and
        $ScriptContent -notmatch 'SupportsShouldProcess') {
        throw 'Potential modifying cmdlets found but SupportsShouldProcess was not detected.'
    }
    'No unsafe modifying pattern detected by generic check.'
}

if ($RunPSScriptAnalyzer) {
    if (Get-Module -ListAvailable -Name PSScriptAnalyzer) {
        try {
            $issues = Invoke-ScriptAnalyzer -Path $ResolvedScriptPath -Severity Warning,Error
            if ($issues) {
                Add-TestResult -Test 'PSScriptAnalyzer' -Status 'WARN' -Details (($issues | ForEach-Object { "[$($_.Severity)] $($_.RuleName): $($_.Message)" }) -join ' | ')
            }
            else {
                Add-TestResult -Test 'PSScriptAnalyzer' -Status 'PASS' -Details 'No warnings or errors.'
            }
        }
        catch {
            Add-TestResult -Test 'PSScriptAnalyzer' -Status 'FAIL' -Details $_.Exception.Message
        }
    }
    else {
        Add-TestResult -Test 'PSScriptAnalyzer' -Status 'SKIP' -Details 'PSScriptAnalyzer is not installed.'
    }
}

# ---------------------------------------------------------------------
# SCRIPT-SPECIFIC TESTS
# Add tests for the productive script here, for example:
# - AD module availability
# - SearchBase validation
# - Wildcard filter behaviour
# - Expected object properties
# - CSV / JSON / XML / TXT export
# - Invalid parameter handling
# - Empty result handling
# - Access denied handling
# - Offline / unavailable dependency handling
# - -WhatIf behaviour
# ---------------------------------------------------------------------

$Results | Format-Table -AutoSize

$failed = @($Results | Where-Object Status -eq 'FAIL')
$warnings = @($Results | Where-Object Status -eq 'WARN')

Write-Host ""
Write-Host "Tests: $($Results.Count) | Failed: $($failed.Count) | Warnings: $($warnings.Count)"

if ($failed.Count -gt 0) {
    exit 1
}

exit 0
