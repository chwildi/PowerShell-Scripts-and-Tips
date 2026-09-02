#requires -Version 7.0
<#
.SYNOPSIS
    Kundenneutrales Werkzeug zum Sichern und Wiederherstellen lokaler Windows-Benutzerdaten.

.DESCRIPTION
    Dieses Skript ist fuer wiederverwendbare Kundenumgebungen und eine Veroeffentlichung
    auf GitHub ausgelegt. Ohne Parameter wird ausschliesslich eine sichere Vorpruefung
    (Mode = Audit) ausgefuehrt. Export und Import muessen bewusst gewaehlt werden.

    Cloud-synchronisierte oder durch Microsoft 365 bereitgestellte Daten werden
    standardmaessig nicht kopiert. Dazu gehoeren insbesondere OneDrive-,
    SharePoint-, Dropbox-, Google-Drive-, iCloud- und Box-Synchronisationspfade.

    Lokale Favoriten und Lesezeichen aller erkannten unterstuetzten Browserprofile
    werden gesichert. Kennwoerter, Cookies, Sitzungen, Formulardaten und andere
    Anmeldedaten werden ausdruecklich nicht migriert.

.NOTES
    Author: Hubert Josef Inderwildi
    License: MIT
    Version: 2.1.1
    Requires: Windows, PowerShell 7+, robocopy.exe fuer Export/Import

.SECURITY
    WLAN-Profile koennen bei aktiviertem Klartext-Export sensible Schluessel enthalten.
    Diese Funktion ist standardmaessig deaktiviert und benoetigt eine zusaetzliche
    explizite Freigabe mit -AllowClearTextWifiKeys.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [ValidateSet('Audit', 'Export', 'Import')]
    [string]$Mode,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$BackupRoot,

    [Parameter()]
    [switch]$IncludeDownloads,

    [Parameter()]
    [switch]$IncludeWifiProfiles,

    [Parameter()]
    [switch]$AllowClearTextWifiKeys,

    [Parameter()]
    [switch]$SkipNetworkDriveRestore,

    [Parameter()]
    [switch]$SkipPrinterRestore,

    [Parameter()]
    [switch]$DisableLogging
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ============================================================================
# CONFIGURATION BLOCK
# Sichere Standardwerte. Parameter oben ueberschreiben diese Werte.
# ============================================================================
$Configuration = [ordered]@{
    Mode                       = 'Audit'
    # Bewusst NICHT "Eigene Dokumente": Dieser Ordner liegt oft in OneDrive.
    # Liegt das Skript z. B. auf D:\, wird D:\WindowsUserMigration verwendet.
    BackupRoot                 = Join-Path $PSScriptRoot 'WindowsUserMigration'
    IncludeDownloads           = $false
    IncludeWifiProfiles        = $false
    AllowClearTextWifiKeys     = $false
    SkipNetworkDriveRestore    = $false
    SkipPrinterRestore         = $false
    RobocopyRetryCount         = 2
    RobocopyWaitSeconds        = 2
    ExcludedFilePatterns       = @('*.ost', '*.tmp')
    ExcludeCloudBackedData     = $true
    ExcludeOfficeCloudData     = $true
    AdditionalCloudRoots       = @()
    BrowserProcesses           = @('chrome', 'msedge', 'firefox', 'brave', 'vivaldi', 'opera', 'opera_gx')
    EnableLogging              = $true
    LogDirectoryName           = 'Logs'
    ScriptVersion              = '2.1.1'
}

if ($PSBoundParameters.ContainsKey('Mode'))                    { $Configuration.Mode = $Mode }
if ($PSBoundParameters.ContainsKey('BackupRoot'))              { $Configuration.BackupRoot = $BackupRoot }
if ($PSBoundParameters.ContainsKey('IncludeDownloads'))        { $Configuration.IncludeDownloads = [bool]$IncludeDownloads }
if ($PSBoundParameters.ContainsKey('IncludeWifiProfiles'))     { $Configuration.IncludeWifiProfiles = [bool]$IncludeWifiProfiles }
if ($PSBoundParameters.ContainsKey('AllowClearTextWifiKeys'))  { $Configuration.AllowClearTextWifiKeys = [bool]$AllowClearTextWifiKeys }
if ($PSBoundParameters.ContainsKey('SkipNetworkDriveRestore')) { $Configuration.SkipNetworkDriveRestore = [bool]$SkipNetworkDriveRestore }
if ($PSBoundParameters.ContainsKey('SkipPrinterRestore'))      { $Configuration.SkipPrinterRestore = [bool]$SkipPrinterRestore }
if ($DisableLogging)                                           { $Configuration.EnableLogging = $false }

$script:MigrationLogFile = $null

function Initialize-MigrationLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Settings
    )

    if (-not $Settings.EnableLogging) {
        return
    }

    try {
        $logRoot = Join-Path -Path (Get-Location).Path -ChildPath $Settings.LogDirectoryName
        if (-not (Test-Path -LiteralPath $logRoot -PathType Container)) {
            New-Item -Path $logRoot -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }

        $scriptName = [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
        if ([string]::IsNullOrWhiteSpace($scriptName)) {
            $scriptName = 'Migriere-WindowsBenutzer'
        }

        $script:MigrationLogFile = Join-Path -Path $logRoot -ChildPath (
            '{0}_{1}.log' -f $scriptName, (Get-Date -Format 'yyyyMMdd_HHmmss')
        )
    }
    catch {
        Write-Warning "Logging konnte nicht initialisiert werden: $($_.Exception.Message)"
        $script:MigrationLogFile = $null
    }
}

function Write-MigrationLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter()]
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line

    if ($Configuration.EnableLogging -and $script:MigrationLogFile) {
        try {
            Add-Content -LiteralPath $script:MigrationLogFile -Value $line -Encoding utf8 -ErrorAction Stop
        }
        catch {
            Write-Warning "Logdatei konnte nicht geschrieben werden: $($_.Exception.Message)"
        }
    }
}

function New-DirectoryIfMissing {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        if ($PSCmdlet.ShouldProcess($Path, 'Create directory')) {
            New-Item -ItemType Directory -Path $Path -Force -ErrorAction Stop | Out-Null
        }
    }
}

function Get-CurrentUserFolderPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Environment+SpecialFolder]$SpecialFolder,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FallbackName
    )

    $resolvedPath = [Environment]::GetFolderPath($SpecialFolder)
    if ([string]::IsNullOrWhiteSpace($resolvedPath)) {
        $resolvedPath = Join-Path $env:USERPROFILE $FallbackName
        Write-MigrationLog -Message "Windows lieferte keinen Pfad fuer '$SpecialFolder'. Ersatzpfad wird verwendet: '$resolvedPath'." -Level WARN
    }

    return $resolvedPath
}

function Invoke-SafeRobocopy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Source,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Destination,

        [Parameter()]
        [string[]]$ExcludeDirectories = @(),

        [Parameter()]
        [string[]]$ExcludeFiles = @(),

        [Parameter()]
        [ValidateRange(0, 20)]
        [int]$RetryCount = 2,

        [Parameter()]
        [ValidateRange(0, 60)]
        [int]$WaitSeconds = 2
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        Write-MigrationLog -Message "Quelle nicht gefunden und uebersprungen: $Source" -Level WARN
        return [pscustomobject]@{
            Source      = $Source
            Destination = $Destination
            ExitCode    = $null
            Status      = 'Skipped'
        }
    }

    if (-not (Get-Command -Name 'robocopy.exe' -ErrorAction SilentlyContinue)) {
        throw 'robocopy.exe wurde auf diesem Computer nicht gefunden.'
    }

    New-DirectoryIfMissing -Path $Destination -Confirm:$false

    $arguments = @(
        $Source,
        $Destination,
        '/E',
        '/COPY:DAT',
        '/DCOPY:DAT',
        "/R:$RetryCount",
        "/W:$WaitSeconds",
        '/XJ',
        '/FFT',
        '/Z',
        '/NP'
    )

    if ($ExcludeDirectories.Count -gt 0) {
        $arguments += '/XD'
        $arguments += $ExcludeDirectories
    }

    if ($ExcludeFiles.Count -gt 0) {
        $arguments += '/XF'
        $arguments += $ExcludeFiles
    }

    $start = Get-Date

    & robocopy.exe @arguments 2>&1 | ForEach-Object {
        $line = $_.ToString()
        Write-Host $line
        if ($Configuration.EnableLogging -and $script:MigrationLogFile) {
            try {
                Add-Content -LiteralPath $script:MigrationLogFile -Value $line -Encoding utf8 -ErrorAction Stop
            }
            catch {
                Write-Warning "Robocopy-Ausgabe konnte nicht ins Log geschrieben werden: $($_.Exception.Message)"
            }
        }
    }

    $exitCode = $LASTEXITCODE
    $duration = (Get-Date) - $start

    # WICHTIG: Format-Operator verhindert ParserError bei Variablen direkt vor ':'.
    Write-MigrationLog -Message (
        'Robocopy beendet. Exit-Code: {0}. Quelle: {1} -> Ziel: {2}. Dauer: {3:N2}s' -f
        $exitCode,
        $Source,
        $Destination,
        $duration.TotalSeconds
    )

    if ($exitCode -ge 8) {
        throw (
            'Robocopy ist mit Exit-Code {0} fehlgeschlagen. Quelle: {1}. Ziel: {2}. ' +
            'Bitte die vorherige Robocopy-Ausgabe und die Logdatei pruefen.'
        ) -f $exitCode, $Source, $Destination
    }

    return [pscustomobject]@{
        Source      = $Source
        Destination = $Destination
        ExitCode    = $exitCode
        Status      = 'Success'
        DurationSec = [math]::Round($duration.TotalSeconds, 2)
    }
}

function Export-JsonData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $InputObject,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    process {
        $InputObject |
            ConvertTo-Json -Depth 8 |
            Set-Content -LiteralPath $Path -Encoding utf8 -ErrorAction Stop
    }
}

function Copy-OptionalMigrationItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Destination
    )

    if (-not [string]::IsNullOrWhiteSpace($Source) -and (Test-Path -LiteralPath $Source)) {
        New-DirectoryIfMissing -Path (Split-Path -Parent $Destination) -Confirm:$false
        Copy-Item -LiteralPath $Source -Destination $Destination -Force -Recurse -ErrorAction Stop
        Write-MigrationLog -Message "Gesichert: $Source"
    }
}

function Backup-ExistingMigrationItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if (Test-Path -LiteralPath $Path) {
        $backupPath = '{0}.before-migration-{1}' -f $Path, (Get-Date -Format 'yyyyMMdd-HHmmss')
        Move-Item -LiteralPath $Path -Destination $backupPath -Force -ErrorAction Stop
        Write-MigrationLog -Message "Vorhandene Datei wurde vor der Wiederherstellung gesichert als: $backupPath" -Level WARN
    }
}

function Test-UserMigrationPrerequisite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Audit', 'Export', 'Import')]
        [string]$Mode,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$BackupRoot
    )

    $checks = [System.Collections.Generic.List[object]]::new()

    $checks.Add([pscustomobject]@{
        Check  = 'Windows-Betriebssystem'
        Passed = $IsWindows
        Detail = if ($IsWindows) { 'Windows erkannt' } else { 'Dieses Skript unterstuetzt nur Windows' }
    })

    $checks.Add([pscustomobject]@{
        Check  = 'PowerShell 7 oder neuer'
        Passed = ($PSVersionTable.PSVersion.Major -ge 7)
        Detail = $PSVersionTable.PSVersion.ToString()
    })

    $checks.Add([pscustomobject]@{
        Check  = 'Benutzerprofil verfuegbar'
        Passed = -not [string]::IsNullOrWhiteSpace($env:USERPROFILE)
        Detail = [string]$env:USERPROFILE
    })

    $checks.Add([pscustomobject]@{
        Check  = 'Sicherungsziel konfiguriert'
        Passed = -not [string]::IsNullOrWhiteSpace($BackupRoot)
        Detail = $BackupRoot
    })

    if ($Mode -in @('Export', 'Import')) {
        $robocopy = Get-Command -Name 'robocopy.exe' -ErrorAction SilentlyContinue
        $checks.Add([pscustomobject]@{
            Check  = 'robocopy.exe'
            Passed = ($null -ne $robocopy)
            Detail = if ($robocopy) { $robocopy.Source } else { 'Not found' }
        })
    }

    if ($Mode -eq 'Import') {
        $checks.Add([pscustomobject]@{
            Check  = 'Sicherungsquelle vorhanden'
            Passed = (Test-Path -LiteralPath $BackupRoot -PathType Container)
            Detail = $BackupRoot
        })
    }

    return $checks
}

function Get-NormalizedMigrationPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    try {
        return [System.IO.Path]::GetFullPath(
            [Environment]::ExpandEnvironmentVariables($Path)
        ).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
    }
    catch {
        Write-MigrationLog -Message "Pfad konnte nicht normalisiert werden: '$Path'. $($_.Exception.Message)" -Level WARN
        return $Path.TrimEnd('\')
    }
}

function Get-CloudStorageRoot {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string[]]$AdditionalCloudRoots = @()
    )

    $roots = [System.Collections.Generic.List[string]]::new()
    $candidateVariables = @(
        'OneDrive',
        'OneDriveCommercial',
        'OneDriveConsumer',
        'Dropbox',
        'GoogleDrive',
        'iCloudDrive'
    )

    foreach ($variableName in $candidateVariables) {
        $value = [Environment]::GetEnvironmentVariable($variableName)
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $roots.Add($value)
        }
    }

    foreach ($knownFolder in @(
        (Join-Path $env:USERPROFILE 'OneDrive'),
        (Join-Path $env:USERPROFILE 'Dropbox'),
        (Join-Path $env:USERPROFILE 'Google Drive'),
        (Join-Path $env:USERPROFILE 'My Drive'),
        (Join-Path $env:USERPROFILE 'iCloudDrive'),
        (Join-Path $env:USERPROFILE 'Box')
    )) {
        if (Test-Path -LiteralPath $knownFolder -PathType Container) {
            $roots.Add($knownFolder)
        }
    }

    if ($IsWindows) {
        foreach ($accountKey in @(
            'HKCU:\Software\Microsoft\OneDrive\Accounts\*',
            'HKCU:\Software\SyncEngines\Providers\OneDrive\*'
        )) {
            Get-ItemProperty -Path $accountKey -ErrorAction SilentlyContinue |
                ForEach-Object {
                    foreach ($propertyName in @('UserFolder', 'MountPoint')) {
                        $property = $_.PSObject.Properties[$propertyName]
                        $propertyValue = if ($null -ne $property) { $property.Value } else { $null }
                        if (-not [string]::IsNullOrWhiteSpace($propertyValue)) {
                            $roots.Add([string]$propertyValue)
                        }
                    }
                }
        }
    }

    foreach ($additionalRoot in $AdditionalCloudRoots) {
        if (-not [string]::IsNullOrWhiteSpace($additionalRoot)) {
            $roots.Add($additionalRoot)
        }
    }

    return @(
        $roots |
            ForEach-Object { Get-NormalizedMigrationPath -Path $_ } |
            Sort-Object -Unique
    )
}

function Test-IsCloudBackedPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter()]
        [string[]]$CloudRoots = @()
    )

    $normalizedPath = Get-NormalizedMigrationPath -Path $Path

    foreach ($cloudRoot in $CloudRoots) {
        $normalizedRoot = Get-NormalizedMigrationPath -Path $cloudRoot
        if (
            $normalizedPath.Equals($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
            $normalizedPath.StartsWith(
                "$normalizedRoot$([System.IO.Path]::DirectorySeparatorChar)",
                [System.StringComparison]::OrdinalIgnoreCase
            )
        ) {
            return $true
        }
    }

    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            Write-MigrationLog -Message "Reparse-Point wird vorsichtshalber als Cloud-/Umleitungspfad behandelt: $Path" -Level WARN
            return $true
        }
    }
    catch {
        # Nicht vorhandene Ordner werden spaeter durch die Kopierfunktion behandelt.
    }

    return $false
}

function Get-BrowserBookmarkDefinition {
    [CmdletBinding()]
    param()

    return @(
        [pscustomobject]@{ Name = 'Microsoft Edge'; Type = 'Chromium'; Root = (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data') },
        [pscustomobject]@{ Name = 'Google Chrome'; Type = 'Chromium'; Root = (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data') },
        [pscustomobject]@{ Name = 'Google Chrome Beta'; Type = 'Chromium'; Root = (Join-Path $env:LOCALAPPDATA 'Google\Chrome Beta\User Data') },
        [pscustomobject]@{ Name = 'Brave'; Type = 'Chromium'; Root = (Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data') },
        [pscustomobject]@{ Name = 'Vivaldi'; Type = 'Chromium'; Root = (Join-Path $env:LOCALAPPDATA 'Vivaldi\User Data') },
        [pscustomobject]@{ Name = 'Opera Stable'; Type = 'Opera'; Root = (Join-Path $env:APPDATA 'Opera Software\Opera Stable') },
        [pscustomobject]@{ Name = 'Opera GX'; Type = 'Opera'; Root = (Join-Path $env:APPDATA 'Opera Software\Opera GX Stable') },
        [pscustomobject]@{ Name = 'Mozilla Firefox'; Type = 'Firefox'; Root = (Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles') }
    )
}

function Export-BrowserBookmarks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DestinationRoot
    )

    $manifest = [System.Collections.Generic.List[object]]::new()

    foreach ($browser in Get-BrowserBookmarkDefinition) {
        if (-not (Test-Path -LiteralPath $browser.Root -PathType Container)) {
            continue
        }

        Write-MigrationLog -Message "Browser erkannt: $($browser.Name). Lokale Lesezeichen werden profilweise gesichert."
        $safeBrowserName = $browser.Name -replace '[^A-Za-z0-9._-]', '_'

        switch ($browser.Type) {
            'Chromium' {
                Get-ChildItem -LiteralPath $browser.Root -Directory -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' -or $_.Name -eq 'Guest Profile' } |
                    ForEach-Object {
                        foreach ($fileName in @('Bookmarks', 'Bookmarks.bak')) {
                            $source = Join-Path $_.FullName $fileName
                            if (Test-Path -LiteralPath $source -PathType Leaf) {
                                $target = Join-Path $DestinationRoot "$safeBrowserName\$($_.Name)\$fileName"
                                Copy-OptionalMigrationItem -Source $source -Destination $target
                                $manifest.Add([pscustomobject]@{ Browser = $browser.Name; Profile = $_.Name; File = $fileName; RelativePath = "$safeBrowserName\$($_.Name)\$fileName" })
                            }
                        }
                    }
            }
            'Opera' {
                foreach ($fileName in @('Bookmarks', 'Bookmarks.bak')) {
                    $source = Join-Path $browser.Root $fileName
                    if (Test-Path -LiteralPath $source -PathType Leaf) {
                        $target = Join-Path $DestinationRoot "$safeBrowserName\Default\$fileName"
                        Copy-OptionalMigrationItem -Source $source -Destination $target
                        $manifest.Add([pscustomobject]@{ Browser = $browser.Name; Profile = 'Default'; File = $fileName; RelativePath = "$safeBrowserName\Default\$fileName" })
                    }
                }
            }
            'Firefox' {
                Get-ChildItem -LiteralPath $browser.Root -Directory -ErrorAction SilentlyContinue |
                    ForEach-Object {
                        foreach ($fileName in @('places.sqlite', 'favicons.sqlite')) {
                            $source = Join-Path $_.FullName $fileName
                            if (Test-Path -LiteralPath $source -PathType Leaf) {
                                $target = Join-Path $DestinationRoot "$safeBrowserName\$($_.Name)\$fileName"
                                Copy-OptionalMigrationItem -Source $source -Destination $target
                                $manifest.Add([pscustomobject]@{ Browser = $browser.Name; Profile = $_.Name; File = $fileName; RelativePath = "$safeBrowserName\$($_.Name)\$fileName" })
                            }
                        }
                    }
            }
        }
    }

    if ($manifest.Count -gt 0) {
        Export-JsonData -InputObject @($manifest) -Path (Join-Path $DestinationRoot 'BrowserBookmarks.json')
    }
    else {
        Write-MigrationLog -Message 'Keine lokalen Browser-Lesezeichen gefunden.' -Level WARN
    }

    return $manifest
}

function Import-BrowserBookmarks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SourceRoot
    )

    $manifestPath = Join-Path $SourceRoot 'BrowserBookmarks.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        Write-MigrationLog -Message 'Kein Browser-Lesezeichenmanifest im Backup gefunden.' -Level WARN
        return
    }

    $definitions = @{}
    foreach ($definition in Get-BrowserBookmarkDefinition) {
        $definitions[$definition.Name] = $definition
    }

    foreach ($item in @(Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop | ConvertFrom-Json)) {
        if (-not $definitions.ContainsKey([string]$item.Browser)) {
            Write-MigrationLog -Message "Unbekannter Browser im Manifest, uebersprungen: $($item.Browser)" -Level WARN
            continue
        }

        $definition = $definitions[[string]$item.Browser]
        $source = Join-Path $SourceRoot ([string]$item.RelativePath)

        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            Write-MigrationLog -Message "Lesezeichendatei fehlt im Backup: $source" -Level WARN
            continue
        }

        $target = switch ($definition.Type) {
            'Chromium' { Join-Path $definition.Root "$($item.Profile)\$($item.File)" }
            'Opera'    { Join-Path $definition.Root ([string]$item.File) }
            'Firefox'  { Join-Path $definition.Root "$($item.Profile)\$($item.File)" }
        }

        if ([string]::IsNullOrWhiteSpace($target)) {
            continue
        }

        Backup-ExistingMigrationItem -Path $target
        New-DirectoryIfMissing -Path (Split-Path -Parent $target) -Confirm:$false
        Copy-Item -LiteralPath $source -Destination $target -Force -ErrorAction Stop
        Write-MigrationLog -Message "Browser-Lesezeichen wiederhergestellt: $($item.Browser), Profil $($item.Profile)"
    }
}

function Export-WindowsUserMigration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BackupRoot,

        [Parameter(Mandatory)]
        [bool]$IncludeDownloads,

        [Parameter(Mandatory)]
        [bool]$IncludeWifiProfiles,

        [Parameter(Mandatory)]
        [bool]$AllowClearTextWifiKeys,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Settings
    )

    $computer = $env:COMPUTERNAME
    $user = $env:USERNAME
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $exportPath = Join-Path $BackupRoot ("{0}_{1}_{2}" -f $computer, $user, $stamp)

    $cloudRoots = @(Get-CloudStorageRoot -AdditionalCloudRoots $Settings.AdditionalCloudRoots)
    if (
        $Settings.ExcludeCloudBackedData -and
        (Test-IsCloudBackedPath -Path $BackupRoot -CloudRoots $cloudRoots)
    ) {
        throw (
            "Das Sicherungsziel '$BackupRoot' liegt in einem Cloud-/Synchronisationspfad. " +
            'Waehlen Sie ein lokales Laufwerk oder eine externe USB-Festplatte.'
        )
    }

    New-DirectoryIfMissing -Path $exportPath -Confirm:$false

    Write-MigrationLog -Message "Export gestartet fuer $env:USERDOMAIN\$user auf $computer."
    Write-MigrationLog -Message "Sicherungsziel: $exportPath"
    Write-MigrationLog -Message "Skriptversion: $($Settings.ScriptVersion); PowerShell: $($PSVersionTable.PSVersion)"

    $identity = [ordered]@{
        ExportVersion  = $Settings.ScriptVersion
        ExportedAt     = (Get-Date).ToString('o')
        ComputerName   = $computer
        UserName       = $user
        UserDomain     = $env:USERDOMAIN
        UserProfile    = $env:USERPROFILE
        WindowsVersion = [Environment]::OSVersion.VersionString
    }

    $identity | Export-JsonData -Path (Join-Path $exportPath 'MigrationInfo.json')

    Write-MigrationLog -Message ("Erkannte Cloud-Stammverzeichnisse: {0}" -f $(
        if ($cloudRoots.Count -gt 0) { $cloudRoots -join '; ' } else { 'keine' }
    ))

    $dataRoot = Join-Path $exportPath 'UserData'
    $folders = [ordered]@{
        Desktop   = Get-CurrentUserFolderPath -SpecialFolder Desktop -FallbackName 'Desktop'
        Documents = Get-CurrentUserFolderPath -SpecialFolder MyDocuments -FallbackName 'Documents'
        Pictures  = Get-CurrentUserFolderPath -SpecialFolder MyPictures -FallbackName 'Pictures'
        Music     = Get-CurrentUserFolderPath -SpecialFolder MyMusic -FallbackName 'Music'
        Videos    = Get-CurrentUserFolderPath -SpecialFolder MyVideos -FallbackName 'Videos'
        Favorites = Get-CurrentUserFolderPath -SpecialFolder Favorites -FallbackName 'Favorites'
    }

    if ($IncludeDownloads) {
        $folders['Downloads'] = Join-Path $env:USERPROFILE 'Downloads'
    }

    foreach ($entry in $folders.GetEnumerator()) {
        if (
            $Settings.ExcludeCloudBackedData -and
            (Test-IsCloudBackedPath -Path $entry.Value -CloudRoots $cloudRoots)
        ) {
            Write-MigrationLog -Message "Cloud-synchronisierter oder umgeleiteter Ordner ausgeschlossen: $($entry.Key) -> $($entry.Value)" -Level WARN
            continue
        }

        Write-MigrationLog -Message "Lokaler Benutzerordner wird exportiert: $($entry.Key)"

        Invoke-SafeRobocopy `
            -Source $entry.Value `
            -Destination (Join-Path $dataRoot $entry.Key) `
            -ExcludeFiles $Settings.ExcludedFilePatterns `
            -RetryCount $Settings.RobocopyRetryCount `
            -WaitSeconds $Settings.RobocopyWaitSeconds |
            Out-Null
    }

    $browserRoot = Join-Path $exportPath 'Browser'
    $runningBrowsers = @(
        Get-Process -Name $Settings.BrowserProcesses -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty ProcessName -Unique
    )
    if ($runningBrowsers.Count -gt 0) {
        Write-MigrationLog -Message (
            'Folgende Browser laufen noch: {0}. Fuer eine konsistente Sicherung sollten sie geschlossen werden.' -f
            ($runningBrowsers -join ', ')
        ) -Level WARN
    }

    Export-BrowserBookmarks -DestinationRoot $browserRoot | Out-Null

    $pstRoot = Join-Path $exportPath 'Outlook-PST'
    New-DirectoryIfMissing -Path $pstRoot -Confirm:$false

    Get-ChildItem -LiteralPath $env:USERPROFILE -Filter '*.pst' -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object {
            -not $Settings.ExcludeCloudBackedData -or
            -not (Test-IsCloudBackedPath -Path $_.FullName -CloudRoots $cloudRoots)
        } |
        ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $pstRoot $_.Name) -Force -ErrorAction Stop
        }

    $inventory = Join-Path $exportPath 'Inventory'
    New-DirectoryIfMissing -Path $inventory -Confirm:$false

    [pscustomobject]@{
        ExcludeCloudBackedData = $Settings.ExcludeCloudBackedData
        ExcludeOfficeCloudData = $Settings.ExcludeOfficeCloudData
        DetectedCloudRoots     = $cloudRoots
        Note                   = 'Cloud-/Microsoft-365-Daten wurden nicht in die Benutzerdatensicherung aufgenommen.'
    } | Export-JsonData -Path (Join-Path $inventory 'CloudExclusionReport.json')

    if (Get-Command -Name Get-Printer -ErrorAction SilentlyContinue) {
        Get-Printer -ErrorAction SilentlyContinue |
            Select-Object Name, DriverName, PortName, Type, Shared, ShareName |
            Export-Csv -LiteralPath (Join-Path $inventory 'Printers.csv') -NoTypeInformation -Encoding utf8
    }

    Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType=4' -ErrorAction SilentlyContinue |
        Select-Object DeviceID, ProviderName, VolumeName |
        Export-Csv -LiteralPath (Join-Path $inventory 'NetworkDrives.csv') -NoTypeInformation -Encoding utf8

    if ($IncludeWifiProfiles) {
        if (-not $AllowClearTextWifiKeys) {
            throw (
                'Der WLAN-Export wurde angefordert, aber der Klartext-Export der WLAN-Schluessel wurde nicht freigegeben. ' +
                'Verwenden Sie -AllowClearTextWifiKeys nur, wenn dieses Risiko bewusst akzeptiert wird.'
            )
        }

        $wifiRoot = Join-Path $exportPath 'WiFi-Profiles-SENSITIVE'
        New-DirectoryIfMissing -Path $wifiRoot -Confirm:$false

        & netsh.exe wlan export profile folder="$wifiRoot" key=clear |
            Out-File -LiteralPath (Join-Path $wifiRoot 'Export-Output.txt') -Encoding utf8

        Write-MigrationLog `
            -Message 'Wi-Fi profiles exported. WARNING: XML files may contain wireless keys in clear text.' `
            -Level WARN
    }

    Write-MigrationLog -Message 'Export erfolgreich abgeschlossen.'

    return [pscustomobject]@{
        Mode   = 'Export'
        Status = 'Success'
        Path   = $exportPath
        User   = "$env:USERDOMAIN\$user"
    }
}

function Find-LatestMigrationBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BackupRoot
    )

    if (Test-Path -LiteralPath (Join-Path $BackupRoot 'MigrationInfo.json')) {
        return $BackupRoot
    }

    return Get-ChildItem -LiteralPath $BackupRoot -Directory -ErrorAction Stop |
        Where-Object {
            Test-Path -LiteralPath (Join-Path $_.FullName 'MigrationInfo.json')
        } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}

function Import-WindowsUserMigration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BackupRoot,

        [Parameter(Mandatory)]
        [bool]$IncludeWifiProfiles,

        [Parameter(Mandatory)]
        [bool]$SkipNetworkDriveRestore,

        [Parameter(Mandatory)]
        [bool]$SkipPrinterRestore,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Settings
    )

    $candidate = Find-LatestMigrationBackup -BackupRoot $BackupRoot

    if ([string]::IsNullOrWhiteSpace($candidate)) {
        throw "Unter '$BackupRoot' wurde keine gueltige Benutzersicherung gefunden."
    }

    $info = Get-Content -LiteralPath (Join-Path $candidate 'MigrationInfo.json') -Raw -ErrorAction Stop |
        ConvertFrom-Json

    Write-MigrationLog -Message (
        'Import gestartet fuer {0}\{1}; Quelle: {2}\{3}.' -f
        $env:USERDOMAIN,
        $env:USERNAME,
        $info.UserDomain,
        $info.UserName
    )

    $dataRoot = Join-Path $candidate 'UserData'
    $targets = [ordered]@{
        Desktop   = Get-CurrentUserFolderPath -SpecialFolder Desktop -FallbackName 'Desktop'
        Documents = Get-CurrentUserFolderPath -SpecialFolder MyDocuments -FallbackName 'Documents'
        Pictures  = Get-CurrentUserFolderPath -SpecialFolder MyPictures -FallbackName 'Pictures'
        Music     = Get-CurrentUserFolderPath -SpecialFolder MyMusic -FallbackName 'Music'
        Videos    = Get-CurrentUserFolderPath -SpecialFolder MyVideos -FallbackName 'Videos'
        Favorites = Get-CurrentUserFolderPath -SpecialFolder Favorites -FallbackName 'Favorites'
        Downloads = Join-Path $env:USERPROFILE 'Downloads'
    }

    foreach ($entry in $targets.GetEnumerator()) {
        $source = Join-Path $dataRoot $entry.Key

        if (Test-Path -LiteralPath $source -PathType Container) {
            Invoke-SafeRobocopy `
                -Source $source `
                -Destination $entry.Value `
                -RetryCount $Settings.RobocopyRetryCount `
                -WaitSeconds $Settings.RobocopyWaitSeconds |
                Out-Null
        }
    }

    $browserRoot = Join-Path $candidate 'Browser'
    Import-BrowserBookmarks -SourceRoot $browserRoot

    $inventory = Join-Path $candidate 'Inventory'

    if (-not $SkipNetworkDriveRestore) {
        $driveFile = Join-Path $inventory 'NetworkDrives.csv'

        if (Test-Path -LiteralPath $driveFile) {
            Import-Csv -LiteralPath $driveFile |
                Where-Object {
                    -not [string]::IsNullOrWhiteSpace($_.ProviderName)
                } |
                ForEach-Object {
                    $letter = $_.DeviceID.TrimEnd(':')

                    try {
                        New-PSDrive `
                            -Name $letter `
                            -PSProvider FileSystem `
                            -Root $_.ProviderName `
                            -Persist `
                            -Scope Global `
                            -ErrorAction Stop |
                            Out-Null

                        Write-MigrationLog -Message "Network drive connected: $($_.DeviceID) -> $($_.ProviderName)"
                    }
                    catch {
                        Write-MigrationLog `
                            -Message "Network drive not connected: $($_.DeviceID) - $($_.Exception.Message)" `
                            -Level WARN
                    }
                }
        }
    }

    if (-not $SkipPrinterRestore) {
        $printerFile = Join-Path $inventory 'Printers.csv'

        if (
            (Test-Path -LiteralPath $printerFile) -and
            (Get-Command -Name Add-Printer -ErrorAction SilentlyContinue)
        ) {
            Import-Csv -LiteralPath $printerFile |
                Where-Object {
                    $_.Name -like '\\*'
                } |
                ForEach-Object {
                    try {
                        Add-Printer -ConnectionName $_.Name -ErrorAction Stop
                        Write-MigrationLog -Message "Network printer added: $($_.Name)"
                    }
                    catch {
                        Write-MigrationLog `
                            -Message "Printer not added: $($_.Name) - $($_.Exception.Message)" `
                            -Level WARN
                    }
                }
        }
    }

    if ($IncludeWifiProfiles) {
        $wifiRoot = Join-Path $candidate 'WiFi-Profiles-SENSITIVE'

        Get-ChildItem -LiteralPath $wifiRoot -Filter '*.xml' -File -ErrorAction SilentlyContinue |
            ForEach-Object {
                & netsh.exe wlan add profile filename="$($_.FullName)" user=current | Out-Null
            }
    }

    $pstRoot = Join-Path $candidate 'Outlook-PST'

    if (Test-Path -LiteralPath $pstRoot -PathType Container) {
        $documentsTarget = Get-CurrentUserFolderPath -SpecialFolder MyDocuments -FallbackName 'Documents'
        $pstTarget = Join-Path $documentsTarget 'Outlook-Files'

        Invoke-SafeRobocopy -Source $pstRoot -Destination $pstTarget | Out-Null

        Write-MigrationLog `
            -Message "PST files copied. Open manually in Outlook if required: $pstTarget" `
            -Level WARN
    }

    Write-MigrationLog -Message 'Import abgeschlossen. Bitte die Logdatei pruefen und Windows neu starten.'

    return [pscustomobject]@{
        Mode   = 'Import'
        Status = 'Success'
        Path   = $candidate
        User   = "$env:USERDOMAIN\$env:USERNAME"
    }
}

function Invoke-WindowsUserMigration {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Settings
    )

    $checks = @(
        Test-UserMigrationPrerequisite `
            -Mode $Settings.Mode `
            -BackupRoot $Settings.BackupRoot
    )

    $checks | Format-Table -AutoSize | Out-Host

    $failedChecks = @(
        $checks | Where-Object {
            -not $_.Passed
        }
    )

    if ($failedChecks.Count -gt 0) {
        throw "Voraussetzungspruefung fehlgeschlagen: $($failedChecks.Check -join ', ')"
    }

    if ($Settings.Mode -eq 'Audit') {
        Write-MigrationLog -Message 'Pruefung abgeschlossen. Es wurden keine Daten veraendert.'
        return $checks
    }

    if ($Settings.Mode -eq 'Export') {
        if ($PSCmdlet.ShouldProcess($Settings.BackupRoot, 'Export current Windows user migration data')) {
            New-DirectoryIfMissing -Path $Settings.BackupRoot -Confirm:$false

            return Export-WindowsUserMigration `
                -BackupRoot $Settings.BackupRoot `
                -IncludeDownloads $Settings.IncludeDownloads `
                -IncludeWifiProfiles $Settings.IncludeWifiProfiles `
                -AllowClearTextWifiKeys $Settings.AllowClearTextWifiKeys `
                -Settings $Settings
        }
    }

    if ($Settings.Mode -eq 'Import') {
        if ($PSCmdlet.ShouldProcess($Settings.BackupRoot, 'Import latest Windows user migration data')) {
            return Import-WindowsUserMigration `
                -BackupRoot $Settings.BackupRoot `
                -IncludeWifiProfiles $Settings.IncludeWifiProfiles `
                -SkipNetworkDriveRestore $Settings.SkipNetworkDriveRestore `
                -SkipPrinterRestore $Settings.SkipPrinterRestore `
                -Settings $Settings
        }
    }
}

try {
    Initialize-MigrationLog -Settings $Configuration

    Write-MigrationLog -Message (
        'Skriptstart. Version: {0}; Modus: {1}; PowerShell: {2}' -f
        $Configuration.ScriptVersion,
        $Configuration.Mode,
        $PSVersionTable.PSVersion
    )

    $result = Invoke-WindowsUserMigration -Settings $Configuration

    Write-MigrationLog -Message 'Skript erfolgreich abgeschlossen.'
    $result
}
catch {
    $technical = $_ | Out-String

    Write-MigrationLog `
        -Message "Kritischer Fehler: $($_.Exception.Message)" `
        -Level ERROR

    Write-MigrationLog `
        -Message (
            'Empfohlene Massnahme: Logdatei und den unmittelbar davor protokollierten Schritt pruefen. ' +
            'Bei Robocopy-Fehlern insbesondere Quelle, Ziel, freien Speicherplatz und Zugriffsrechte kontrollieren.'
        ) `
        -Level ERROR

    Write-MigrationLog `
        -Message "Technische Details: $technical" `
        -Level ERROR

    exit 1
}
