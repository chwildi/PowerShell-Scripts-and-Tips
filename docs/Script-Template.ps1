#requires -Version 7.0

<#
.SYNOPSIS
    Describe the purpose of the script.

.DESCRIPTION
    Provide a detailed description, prerequisites and expected impact.

.PARAMETER WhatIf
    Supported automatically through SupportsShouldProcess for modifying operations.

.EXAMPLE
    .\Script-Template.ps1 -Verbose -WhatIf

.NOTES
    Author: Hubert Inderwildi
    Version: 1.0.0
    Repository: PowerShell-Scripts-and-Tips

    SECURITY:
    Never store passwords, tokens, customer data or other secrets in this file.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR', 'OK')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [$Level] $Message"
}

try {
    Write-Log -Message 'Script started.'

    # Example for a modifying operation:
    # if ($PSCmdlet.ShouldProcess('Target', 'Describe change')) {
    #     # Perform change here.
    # }

    Write-Log -Message 'Script completed successfully.' -Level 'OK'
}
catch {
    Write-Log -Message $_.Exception.Message -Level 'ERROR'
    throw
}
