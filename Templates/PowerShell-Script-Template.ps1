#requires -Version 7.0
<#
.SYNOPSIS
    Safe customer-neutral PowerShell script template.
.DESCRIPTION
    Starting point for repository scripts. The default configuration performs no modifying action.
    Replace placeholder logic and documentation before publication.
.NOTES
    Author      : Hubert Inderwildi
    Repository  : PowerShell-Scripts-and-Tips
    Version     : 1.1.0
    PowerShell  : 7.x
    License     : MIT
#>
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Medium')]
param(
    [Parameter()][ValidateNotNullOrEmpty()][string]$Target,
    [Parameter()][ValidateNotNullOrEmpty()][string]$LogPath,
    [Parameter()][switch]$Force
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# ============================================================================
# CONFIGURATION BLOCK - safe defaults; optional parameters override them.
# ============================================================================
$Configuration=[ordered]@{
    Target='ExampleTarget'
    LogPath=(Join-Path $PSScriptRoot "Logs\$((Get-Date).ToString('yyyyMMdd-HHmmss'))-Script.log")
    Force=$false
    EnableChanges=$false
}
foreach($key in @('Target','LogPath','Force')){if($PSBoundParameters.ContainsKey($key)){$Configuration[$key]=$PSBoundParameters[$key]}}
function Write-ScriptLog{
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Message,[Parameter(Mandatory)][string]$Path,[ValidateSet('INFO','OK','WARN','ERROR')][string]$Level='INFO')
    $entry='[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Level,$Message
    switch($Level){'ERROR'{Write-Error $Message}'WARN'{Write-Warning $Message}default{Write-Verbose $entry}}
    try{$directory=Split-Path -Path $Path -Parent;if($directory -and -not(Test-Path -LiteralPath $directory)){New-Item -ItemType Directory -Path $directory -Force|Out-Null};Add-Content -LiteralPath $Path -Value $entry -Encoding utf8}catch{Write-Warning "Log entry could not be written: $($_.Exception.Message)"}
}
function Invoke-Main{
    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Medium')]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Settings)
    Write-ScriptLog -Message "Starting script for target '$($Settings.Target)'." -Path $Settings.LogPath
    Write-Verbose "Target: $($Settings.Target)"
    Write-Verbose "LogPath: $($Settings.LogPath)"
    Write-Verbose "Force: $($Settings.Force)"
    if(-not $Settings.EnableChanges){Write-ScriptLog -Message 'Safe template mode: no modifying action configured.' -Path $Settings.LogPath -Level INFO;return}
    if($PSCmdlet.ShouldProcess($Settings.Target,'<Describe the change here>')){
        # Place the modifying command here after adapting the template.
        Write-ScriptLog -Message "Change completed for '$($Settings.Target)'." -Path $Settings.LogPath -Level OK
    }
}
try{Write-ScriptLog -Message 'Script started.' -Path $Configuration.LogPath;Invoke-Main -Settings $Configuration -WhatIf:$WhatIfPreference;Write-ScriptLog -Message 'Script completed successfully.' -Path $Configuration.LogPath -Level OK}catch{Write-Warning "Script failed: $($_.Exception.Message)";throw}
