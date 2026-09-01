#requires -Version 7.0
<#
.SYNOPSIS
    Prüft eine Logdatei und veröffentlicht ein PowerShell-Skript nur bei erfolgreicher Prüfung.

.DESCRIPTION
    Release-Gate für das Repository "PowerShell-Scripts-and-Tips".

    Ablauf:
    1. Logdatei validieren (vorhanden, nicht leer, nicht zu alt).
    2. Fehler-/Warnmuster im Log auswerten.
    3. Zielskript auf PowerShell-Syntax prüfen.
    4. Optional PSScriptAnalyzer ausführen.
    5. Status im Zielskript von "Draft" auf "Final" ändern.
    6. Git-Status prüfen.
    7. Zielskript committen und zu GitHub pushen.

    Das Skript arbeitet "fail closed": Bei Unsicherheit oder Fehlern findet
    KEINE Veröffentlichung statt.

.NOTES
    Version : 1.0.0
    Status  : Final
    Author  : Hubert Inderwildi / OpenAI
    Requires: PowerShell 7+, Git; optional PSScriptAnalyzer
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [string]$LogPath,

    [Parameter()]
    [string]$ScriptPath,

    [Parameter()]
    [string]$RepositoryPath,

    [Parameter()]
    [string]$RemoteName,

    [Parameter()]
    [string]$BranchName,

    [Parameter()]
    [ValidateRange(1, 720)]
    [int]$MaximumLogAgeHours,

    [Parameter()]
    [switch]$SkipPSScriptAnalyzer,

    [Parameter()]
    [switch]$DisablePublish,

    [Parameter()]
    [switch]$DisableLogging
)

# ============================================================================
# CONFIGURATION BLOCK
# ============================================================================
$Config = [ordered]@{
    LogPath                  = ''
    ScriptPath               = ''
    RepositoryPath           = (Get-Location).Path
    RemoteName               = 'origin'
    BranchName               = 'main'
    AutoPublish              = $true
    MaximumLogAgeHours       = 24
    TreatWarningsAsErrors    = $false
    RequireSuccessMarker     = $false

    ErrorPatterns = @(
        '(?i)\bERROR\b'
        '(?i)\bFATAL\b'
        '(?i)\bEXCEPTION\b'
        '(?i)\bFAILED\b'
        '(?i)\bFAILURE\b'
        '(?i)\bTERMINATING ERROR\b'
        '(?i)\bACCESS DENIED\b'
        '(?i)\bUNAUTHORIZED\b'
        '(?i)\bSTACK TRACE\b'
        '(?i)\bTRACEBACK\b'
        '(?i)\bCRITICAL\b'
    )

    WarningPatterns = @(
        '(?i)\bWARN(?:ING)?\b'
    )

    IgnorePatterns = @(
        '(?i)\b0\s+errors?\b'
        '(?i)\berrors?\s*[:=]\s*0\b'
        '(?i)\bno\s+errors?\b'
        '(?i)\bwithout\s+errors?\b'
        '(?i)\bkeine\s+fehler\b'
        '(?i)\bohne\s+fehler\b'
        '(?i)\b0\s+failed\b'
        '(?i)\bfailed\s*[:=]\s*0\b'
    )

    SuccessPatterns = @(
        '(?i)\bsuccess\b'
        '(?i)\bsuccessful\b'
        '(?i)\berfolgreich\b'
        '(?i)\bcompleted\b'
        '(?i)\babgeschlossen\b'
    )

    EnableLogging             = $true
    LogDirectoryName          = 'Logs'
    EnablePSScriptAnalyzer    = $true
    FailOnAnalyzerWarning     = $false
}
# ============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSBoundParameters.ContainsKey('LogPath'))            { $Config.LogPath = $LogPath }
if ($PSBoundParameters.ContainsKey('ScriptPath'))         { $Config.ScriptPath = $ScriptPath }
if ($PSBoundParameters.ContainsKey('RepositoryPath'))     { $Config.RepositoryPath = $RepositoryPath }
if ($PSBoundParameters.ContainsKey('RemoteName'))         { $Config.RemoteName = $RemoteName }
if ($PSBoundParameters.ContainsKey('BranchName'))         { $Config.BranchName = $BranchName }
if ($PSBoundParameters.ContainsKey('MaximumLogAgeHours')) { $Config.MaximumLogAgeHours = $MaximumLogAgeHours }
if ($SkipPSScriptAnalyzer)                                { $Config.EnablePSScriptAnalyzer = $false }
if ($DisablePublish)                                      { $Config.AutoPublish = $false }
if ($DisableLogging)                                      { $Config.EnableLogging = $false }

$script:GateLogPath = $null
$script:OriginalScriptContent = $null
$script:ScriptWasModified = $false
$script:CommitCreated = $false

function Write-GateLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR', 'DEBUG')]
        [string]$Level,

        [Parameter(Mandatory)]
        [string]$Message
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $line = '[{0}] [{1}] {2}' -f $timestamp, $Level, $Message

    switch ($Level) {
        'ERROR'   { Write-Error $Message -ErrorAction Continue }
        'WARNING' { Write-Warning $Message }
        default   { Write-Host $line }
    }

    if ($Config.EnableLogging -and $script:GateLogPath) {
        try {
            Add-Content -LiteralPath $script:GateLogPath -Value $line -Encoding utf8 -ErrorAction Stop
        }
        catch {
            Write-Warning "Release-Gate-Log konnte nicht geschrieben werden: $($_.Exception.Message)"
        }
    }
}

function Stop-ReleaseGate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$ExitCode,

        [Parameter(Mandatory)]
        [string]$Message,

        [string]$Recommendation = ''
    )

    Write-GateLog -Level ERROR -Message $Message
    if ($Recommendation) {
        Write-GateLog -Level INFO -Message "Empfohlene Massnahme: $Recommendation"
    }

    if ($script:ScriptWasModified -and -not $script:CommitCreated -and $null -ne $script:OriginalScriptContent) {
        try {
            Set-Content -LiteralPath $Config.ScriptPath -Value $script:OriginalScriptContent -Encoding utf8NoBOM -NoNewline
            Write-GateLog -Level INFO -Message 'Lokale Statusänderung wurde zurückgerollt.'
        }
        catch {
            Write-GateLog -Level ERROR -Message "Rollback fehlgeschlagen: $($_.Exception.Message)"
        }
    }

    exit $ExitCode
}

function Resolve-FullPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$BasePath
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path -Path $BasePath -ChildPath $Path))
}

function Invoke-Git {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [switch]$AllowFailure
    )

    try {
        $output = & git -C $Config.RepositoryPath @Arguments 2>&1
        $exitCode = $LASTEXITCODE

        if ($exitCode -ne 0 -and -not $AllowFailure) {
            throw "git $($Arguments -join ' ') fehlgeschlagen (ExitCode $exitCode): $($output -join [Environment]::NewLine)"
        }

        [pscustomobject]@{
            ExitCode = $exitCode
            Output   = @($output)
        }
    }
    catch {
        if ($AllowFailure) {
            return [pscustomobject]@{
                ExitCode = 999
                Output   = @($_.Exception.Message)
            }
        }
        throw
    }
}

function Test-LogFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Logdatei wurde nicht gefunden: $Path"
    }

    $file = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($file.Length -le 0) {
        throw "Logdatei ist leer: $Path"
    }

    $age = (Get-Date) - $file.LastWriteTime
    if ($age.TotalHours -gt $Config.MaximumLogAgeHours) {
        throw ('Logdatei ist {0:N1} Stunden alt. Maximal erlaubt: {1} Stunden.' -f $age.TotalHours, $Config.MaximumLogAgeHours)
    }

    $lines = @(Get-Content -LiteralPath $Path -ErrorAction Stop)
    if ($lines.Count -eq 0) {
        throw 'Logdatei enthält keine auswertbaren Zeilen.'
    }

    $findings = [System.Collections.Generic.List[object]]::new()
    $successMarkerFound = $false

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = [string]$lines[$i]
        $ignored = $false

        foreach ($pattern in $Config.IgnorePatterns) {
            if ($line -match $pattern) {
                $ignored = $true
                break
            }
        }

        foreach ($successPattern in $Config.SuccessPatterns) {
            if ($line -match $successPattern) {
                $successMarkerFound = $true
                break
            }
        }

        if ($ignored) { continue }

        foreach ($pattern in $Config.ErrorPatterns) {
            if ($line -match $pattern) {
                $findings.Add([pscustomobject]@{
                    Severity   = 'Error'
                    LineNumber = $i + 1
                    Text       = $line.Trim()
                    Pattern    = $pattern
                })
                break
            }
        }

        foreach ($pattern in $Config.WarningPatterns) {
            if ($line -match $pattern) {
                $findings.Add([pscustomobject]@{
                    Severity   = 'Warning'
                    LineNumber = $i + 1
                    Text       = $line.Trim()
                    Pattern    = $pattern
                })
                break
            }
        }
    }

    $errors = @($findings | Where-Object Severity -eq 'Error')
    $warnings = @($findings | Where-Object Severity -eq 'Warning')

    [pscustomobject]@{
        Path               = $Path
        SizeBytes          = $file.Length
        LastWriteTime      = $file.LastWriteTime
        LineCount          = $lines.Count
        ErrorCount         = $errors.Count
        WarningCount       = $warnings.Count
        SuccessMarkerFound = $successMarkerFound
        Findings           = @($findings)
    }
}

function Test-PowerShellSyntax {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$parseErrors)
    return @($parseErrors)
}

function Invoke-ScriptAnalyzerGate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not $Config.EnablePSScriptAnalyzer) {
        return [pscustomobject]@{ WasRun = $false; Findings = @() }
    }

    if (-not (Get-Command -Name Invoke-ScriptAnalyzer -ErrorAction SilentlyContinue)) {
        throw 'PSScriptAnalyzer ist nicht installiert oder Invoke-ScriptAnalyzer wurde nicht gefunden.'
    }

    $findings = @(Invoke-ScriptAnalyzer -Path $Path -Recurse:$false -ErrorAction Stop)
    [pscustomobject]@{ WasRun = $true; Findings = $findings }
}

function Set-ScriptStatusFinal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $content = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    $script:OriginalScriptContent = $content

    if ($content -match '(?im)^\s*#\s*Status\s*[:=]\s*Final\s*$' -or
        $content -match '(?im)^\s*\.STATUS\s+Final\s*$') {
        return [pscustomobject]@{ Changed = $false; AlreadyFinal = $true }
    }

    $newContent = $content
    $newContent = $newContent -replace '(?im)^(\s*#\s*Status\s*[:=]\s*)Draft(\s*)$', '${1}Final${2}'

    if ($newContent -eq $content) {
        $newContent = $newContent -replace '(?im)^(\s*\.STATUS\s+)Draft(\s*)$', '${1}Final${2}'
    }

    if ($newContent -eq $content) {
        throw 'Keine unterstützte Statusmarkierung "Draft" im Zielskript gefunden. Erwartet z.B. "# Status : Draft".'
    }

    Set-Content -LiteralPath $Path -Value $newContent -Encoding utf8NoBOM -NoNewline -ErrorAction Stop
    $script:ScriptWasModified = $true
    [pscustomobject]@{ Changed = $true; AlreadyFinal = $false }
}

function Test-GitRepositoryState {
    [CmdletBinding()]
    param()

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw 'Git wurde nicht gefunden. Installiere Git und stelle sicher, dass git.exe über PATH erreichbar ist.'
    }

    $inside = Invoke-Git -Arguments @('rev-parse', '--is-inside-work-tree')
    if (($inside.Output -join '').Trim() -ne 'true') {
        throw "Pfad ist kein Git-Repository: $($Config.RepositoryPath)"
    }

    $remote = Invoke-Git -Arguments @('remote', 'get-url', $Config.RemoteName)
    if (-not (($remote.Output -join '').Trim())) {
        throw "Git-Remote '$($Config.RemoteName)' ist nicht konfiguriert."
    }

    $currentBranch = ((Invoke-Git -Arguments @('branch', '--show-current')).Output -join '').Trim()
    if (-not $currentBranch) {
        throw 'Detached HEAD erkannt. Veröffentlichung wird aus Sicherheitsgründen abgebrochen.'
    }

    if ($Config.BranchName -and $currentBranch -ne $Config.BranchName) {
        throw "Aktiver Branch '$currentBranch' entspricht nicht dem erwarteten Branch '$($Config.BranchName)'."
    }

    $status = @((Invoke-Git -Arguments @('status', '--porcelain')).Output)
    [pscustomobject]@{
        Branch = $currentBranch
        Remote = ($remote.Output -join '').Trim()
        Status = $status
    }
}

function Test-OnlyTargetScriptChanged {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TargetPath
    )

    $repoRoot = ((Invoke-Git -Arguments @('rev-parse', '--show-toplevel')).Output -join '').Trim()
    $relativeTarget = [System.IO.Path]::GetRelativePath($repoRoot, $TargetPath).Replace('\', '/')
    $changes = @((Invoke-Git -Arguments @('status', '--porcelain')).Output | Where-Object { $_ })
    $unexpected = [System.Collections.Generic.List[string]]::new()

    foreach ($change in $changes) {
        if ($change.Length -lt 4) {
            $unexpected.Add($change)
            continue
        }

        $path = $change.Substring(3).Trim().Replace('\', '/')
        if ($path -ne $relativeTarget) {
            $unexpected.Add($change)
        }
    }

    [pscustomobject]@{
        RelativeTarget = $relativeTarget
        Changes        = $changes
        Unexpected     = @($unexpected)
    }
}

function Publish-TargetScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TargetPath
    )

    $repoRoot = ((Invoke-Git -Arguments @('rev-parse', '--show-toplevel')).Output -join '').Trim()
    $relativeTarget = [System.IO.Path]::GetRelativePath($repoRoot, $TargetPath).Replace('\', '/')
    $scriptName = [System.IO.Path]::GetFileName($TargetPath)

    Invoke-Git -Arguments @('add', '--', $relativeTarget) | Out-Null

    $staged = @((Invoke-Git -Arguments @('diff', '--cached', '--name-only')).Output | Where-Object { $_ })
    if ($staged.Count -ne 1 -or $staged[0].Trim().Replace('\', '/') -ne $relativeTarget) {
        throw "Sicherheitsprüfung fehlgeschlagen: Im Commit ist nicht exakt nur '$relativeTarget' enthalten."
    }

    $commitMessage = "Promote $scriptName from Draft to Final after clean log validation"
    Invoke-Git -Arguments @('commit', '-m', $commitMessage, '--', $relativeTarget) | Out-Null
    $script:CommitCreated = $true

    Invoke-Git -Arguments @('push', $Config.RemoteName, $Config.BranchName) | Out-Null
    $commitSha = ((Invoke-Git -Arguments @('rev-parse', 'HEAD')).Output -join '').Trim()

    [pscustomobject]@{
        CommitSha = $commitSha
        Branch    = $Config.BranchName
        Remote    = $Config.RemoteName
        File      = $relativeTarget
    }
}

try {
    $Config.RepositoryPath = Resolve-FullPath -Path $Config.RepositoryPath -BasePath (Get-Location).Path

    if ($Config.EnableLogging) {
        $logDirectory = Join-Path -Path (Get-Location).Path -ChildPath $Config.LogDirectoryName
        if (-not (Test-Path -LiteralPath $logDirectory -PathType Container)) {
            New-Item -Path $logDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }

        $script:GateLogPath = Join-Path -Path $logDirectory -ChildPath (
            'Test-ScriptLogRelease-TEST_{0}.log' -f (Get-Date -Format 'yyyyMMdd_HHmmss')
        )
    }

    Write-GateLog -Level INFO -Message 'Release-Gate gestartet.'
    Write-GateLog -Level INFO -Message "Repository: $($Config.RepositoryPath)"

    if ([string]::IsNullOrWhiteSpace($Config.LogPath)) {
        Stop-ReleaseGate -ExitCode 10 -Message 'Keine Logdatei angegeben.' -Recommendation 'LogPath im CONFIGURATION BLOCK setzen oder -LogPath verwenden.'
    }

    if ([string]::IsNullOrWhiteSpace($Config.ScriptPath)) {
        Stop-ReleaseGate -ExitCode 11 -Message 'Kein Zielskript angegeben.' -Recommendation 'ScriptPath im CONFIGURATION BLOCK setzen oder -ScriptPath verwenden.'
    }

    $Config.LogPath = Resolve-FullPath -Path $Config.LogPath -BasePath $Config.RepositoryPath
    $Config.ScriptPath = Resolve-FullPath -Path $Config.ScriptPath -BasePath $Config.RepositoryPath

    if (-not (Test-Path -LiteralPath $Config.ScriptPath -PathType Leaf)) {
        Stop-ReleaseGate -ExitCode 12 -Message "Zielskript nicht gefunden: $($Config.ScriptPath)"
    }

    if ([System.IO.Path]::GetExtension($Config.ScriptPath) -ne '.ps1') {
        Stop-ReleaseGate -ExitCode 13 -Message 'Das Ziel muss eine .ps1-Datei sein.'
    }

    Write-GateLog -Level INFO -Message "Zielskript: $($Config.ScriptPath)"
    Write-GateLog -Level INFO -Message "Zu prüfendes Log: $($Config.LogPath)"

    $gitState = Test-GitRepositoryState
    $preExistingChanges = @($gitState.Status | Where-Object { $_ })
    if ($preExistingChanges.Count -gt 0) {
        Stop-ReleaseGate -ExitCode 20 `
            -Message "Repository enthält bereits uncommittete Änderungen: $($preExistingChanges -join '; ')" `
            -Recommendation 'Änderungen zuerst committen, stashen oder verwerfen.'
    }

    $logResult = Test-LogFile -Path $Config.LogPath
    Write-GateLog -Level INFO -Message (
        "Log ausgewertet: {0} Zeilen, {1} Fehler, {2} Warnungen." -f
        $logResult.LineCount, $logResult.ErrorCount, $logResult.WarningCount
    )

    foreach ($finding in $logResult.Findings) {
        $level = if ($finding.Severity -eq 'Error') { 'ERROR' } else { 'WARNING' }
        Write-GateLog -Level $level -Message "Log Zeile $($finding.LineNumber): $($finding.Text)"
    }

    if ($logResult.ErrorCount -gt 0) {
        Stop-ReleaseGate -ExitCode 30 `
            -Message "Release blockiert: Das Log enthält $($logResult.ErrorCount) erkannte Fehler." `
            -Recommendation 'Fehler im Quellskript beheben, erneut testen und ein neues sauberes Log erzeugen.'
    }

    if ($Config.TreatWarningsAsErrors -and $logResult.WarningCount -gt 0) {
        Stop-ReleaseGate -ExitCode 31 -Message "Release blockiert: Das Log enthält $($logResult.WarningCount) Warnungen und TreatWarningsAsErrors ist aktiviert."
    }

    if ($Config.RequireSuccessMarker -and -not $logResult.SuccessMarkerFound) {
        Stop-ReleaseGate -ExitCode 32 -Message 'Release blockiert: Kein definierter Erfolgsmarker im Log gefunden.'
    }

    $parseErrors = @(Test-PowerShellSyntax -Path $Config.ScriptPath)
    if ($parseErrors.Count -gt 0) {
        foreach ($parseError in $parseErrors) {
            Write-GateLog -Level ERROR -Message "Syntaxfehler: $($parseError.Message)"
        }
        Stop-ReleaseGate -ExitCode 40 -Message "Release blockiert: $($parseErrors.Count) PowerShell-Syntaxfehler erkannt."
    }

    Write-GateLog -Level SUCCESS -Message 'PowerShell-Syntaxprüfung erfolgreich.'

    try {
        $analyzer = Invoke-ScriptAnalyzerGate -Path $Config.ScriptPath
        if ($analyzer.WasRun) {
            $analyzerErrors = @($analyzer.Findings | Where-Object Severity -eq 'Error')
            $analyzerWarnings = @($analyzer.Findings | Where-Object Severity -eq 'Warning')

            foreach ($finding in $analyzer.Findings) {
                $level = if ($finding.Severity -eq 'Error') { 'ERROR' } else { 'WARNING' }
                Write-GateLog -Level $level -Message "PSScriptAnalyzer [$($finding.RuleName)] Zeile $($finding.Line): $($finding.Message)"
            }

            if ($analyzerErrors.Count -gt 0) {
                Stop-ReleaseGate -ExitCode 41 -Message "Release blockiert: PSScriptAnalyzer meldet $($analyzerErrors.Count) Fehler."
            }

            if ($Config.FailOnAnalyzerWarning -and $analyzerWarnings.Count -gt 0) {
                Stop-ReleaseGate -ExitCode 42 -Message "Release blockiert: PSScriptAnalyzer meldet $($analyzerWarnings.Count) Warnungen."
            }

            Write-GateLog -Level SUCCESS -Message 'PSScriptAnalyzer-Prüfung erfolgreich.'
        }
        else {
            Write-GateLog -Level INFO -Message 'PSScriptAnalyzer-Prüfung wurde deaktiviert.'
        }
    }
    catch {
        Stop-ReleaseGate -ExitCode 43 `
            -Message "PSScriptAnalyzer konnte nicht ausgeführt werden: $($_.Exception.Message)" `
            -Recommendation 'PSScriptAnalyzer installieren oder nur bewusst mit -SkipPSScriptAnalyzer überspringen.'
    }

    $statusResult = Set-ScriptStatusFinal -Path $Config.ScriptPath
    if ($statusResult.AlreadyFinal) {
        Write-GateLog -Level INFO -Message 'Zielskript ist bereits Final. Keine Statusänderung erforderlich.'
    }
    else {
        Write-GateLog -Level SUCCESS -Message 'Status wurde von Draft auf Final geändert.'
    }

    if (-not $statusResult.Changed) {
        Write-GateLog -Level SUCCESS -Message 'Release-Gate erfolgreich beendet; keine Git-Änderung erforderlich.'
        exit 0
    }

    $changeCheck = Test-OnlyTargetScriptChanged -TargetPath $Config.ScriptPath
    if ($changeCheck.Unexpected.Count -gt 0) {
        Stop-ReleaseGate -ExitCode 50 -Message "Release blockiert: Unerwartete zusätzliche Dateien wurden verändert: $($changeCheck.Unexpected -join '; ')"
    }

    if (-not $Config.AutoPublish) {
        Write-GateLog -Level SUCCESS -Message 'Alle Prüfungen bestanden. AutoPublish ist deaktiviert; Datei bleibt lokal auf Final.'
        exit 0
    }

    if ($PSCmdlet.ShouldProcess(
        "$($Config.RemoteName)/$($Config.BranchName)",
        "Statusänderung für '$($Config.ScriptPath)' committen und zu GitHub pushen"
    )) {
        $publishResult = Publish-TargetScript -TargetPath $Config.ScriptPath
        Write-GateLog -Level SUCCESS -Message (
            "FINAL veröffentlicht. Commit=$($publishResult.CommitSha), Branch=$($publishResult.Branch), Datei=$($publishResult.File)"
        )
        exit 0
    }

    Write-GateLog -Level WARNING -Message 'Veröffentlichung durch WhatIf/Bestätigungsabbruch nicht ausgeführt.'
    exit 0
}
catch {
    $technical = $_ | Out-String
    Write-GateLog -Level ERROR -Message "Unerwarteter Fehler: $($_.Exception.Message)"
    Write-GateLog -Level DEBUG -Message "Technische Details: $technical"

    if ($script:ScriptWasModified -and -not $script:CommitCreated -and $null -ne $script:OriginalScriptContent) {
        try {
            Set-Content -LiteralPath $Config.ScriptPath -Value $script:OriginalScriptContent -Encoding utf8NoBOM -NoNewline
            Write-GateLog -Level INFO -Message 'Lokale Statusänderung wurde nach unerwartetem Fehler zurückgerollt.'
        }
        catch {
            Write-GateLog -Level ERROR -Message "Rollback fehlgeschlagen: $($_.Exception.Message)"
        }
    }

    exit 99
}
