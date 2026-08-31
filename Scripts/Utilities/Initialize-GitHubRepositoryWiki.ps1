#requires -Version 7.0
<#
.SYNOPSIS
    Initialisiert oder synchronisiert das GitHub Wiki eines Repositorys aus versionierten Markdown-Quellen.
.DESCRIPTION
    Dieses kundenneutrale Skript verwaltet ein GitHub Wiki ueber dessen Git-Repository (<owner>/<repo>.wiki.git).
    Ohne Parameter wird ein sicherer Audit-Modus ausgefuehrt. Initialize und Sync muessen explizit gewaehlt werden.

    Das Skript kann vorhandene Repository-Dokumente wie docs/Wiki-Home.md, SCRIPT-CATALOG.md,
    CHANGELOG.md und docs/Compatibility-Matrix.md in Wiki-Seiten uebernehmen. Zusaetzlich werden
    _Sidebar.md und _Footer.md erzeugt.

    Voraussetzung: Das GitHub Wiki muss einmalig aktiviert und mindestens eine Wiki-Seite vorhanden sein,
    damit das .wiki.git Repository geklont werden kann.
.NOTES
    Author  : Hubert Inderwildi
    Version : 1.0.0.0
    License : MIT
    PowerShell: 7+
#>
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Medium')]
param(
    [ValidateSet('Audit','Initialize','Sync')][string]$Mode,
    [string]$Repository='chwildi/PowerShell-Scripts-and-Tips',
    [string]$RepositoryRoot=(Get-Location).Path,
    [string]$WorkingDirectory=(Join-Path ([System.IO.Path]::GetTempPath()) 'GitHubWikiSync'),
    [switch]$Push,
    [switch]$KeepWorkingDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

# ============================================================================
# CONFIGURATION BLOCK - safe defaults; parameters override when provided.
# ============================================================================
$Configuration=[ordered]@{
    Mode='Audit'
    Repository='chwildi/PowerShell-Scripts-and-Tips'
    RepositoryRoot=(Get-Location).Path
    WorkingDirectory=(Join-Path ([System.IO.Path]::GetTempPath()) 'GitHubWikiSync')
    Push=$false
    KeepWorkingDirectory=$false
    SourceMap=[ordered]@{
        'Home.md'='docs/Wiki-Home.md'
        'Script-Catalog.md'='SCRIPT-CATALOG.md'
        'Changelog.md'='CHANGELOG.md'
        'Compatibility-Matrix.md'='docs/Compatibility-Matrix.md'
        'Migration-Migriere-WindowsBenutzer.md'='docs/Migriere-WindowsBenutzer.md'
    }
}
foreach($key in @('Mode','Repository','RepositoryRoot','WorkingDirectory','Push','KeepWorkingDirectory')){if($PSBoundParameters.ContainsKey($key)){$Configuration[$key]=$PSBoundParameters[$key]}}

function Test-GitCommand{
    [CmdletBinding()]
    param()
    [bool](Get-Command git -ErrorAction SilentlyContinue)
}
function Get-GitHubWikiUrl{
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Repository)
    if($Repository -notmatch '^[^/]+/[^/]+$'){throw "Repository must use owner/name format: $Repository"}
    "https://github.com/$Repository.wiki.git"
}
function Get-WikiSourceStatus{
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)][System.Collections.IDictionary]$SourceMap)
    foreach($item in $SourceMap.GetEnumerator()){
        $source=Join-Path $RepositoryRoot $item.Value
        [pscustomobject]@{WikiPage=$item.Key;Source=$item.Value;Exists=(Test-Path -LiteralPath $source -PathType Leaf);FullPath=$source}
    }
}
function New-WikiNavigationContent{
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Pages)
    $links=$Pages|Where-Object{$_ -notin @('_Sidebar.md','_Footer.md')}|ForEach-Object{"- [$(($_ -replace '\.md$','') -replace '-',' ')]($(($_ -replace '\.md$','')))"}
    "# Navigation`n`n$($links -join "`n")`n"
}
function Initialize-WikiWorkingCopy{
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([Parameter(Mandatory)][string]$WikiUrl,[Parameter(Mandatory)][string]$WorkingDirectory,[Parameter(Mandatory)][ValidateSet('Initialize','Sync')][string]$Mode)
    if(Test-Path -LiteralPath $WorkingDirectory){if($PSCmdlet.ShouldProcess($WorkingDirectory,'Remove existing wiki working directory')){Remove-Item -LiteralPath $WorkingDirectory -Recurse -Force}}
    $parent=Split-Path -Parent $WorkingDirectory
    if(-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
    if($PSCmdlet.ShouldProcess($WikiUrl,"Clone GitHub Wiki for $Mode")){
        & git clone $WikiUrl $WorkingDirectory
        if($LASTEXITCODE -ne 0){throw "Git clone failed. Ensure the GitHub Wiki is enabled and at least one page exists: $WikiUrl"}
    }
}
function Copy-WikiSources{
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)][string]$WorkingDirectory,[Parameter(Mandatory)][System.Collections.IDictionary]$SourceMap)
    $written=[System.Collections.Generic.List[string]]::new()
    foreach($item in $SourceMap.GetEnumerator()){
        $source=Join-Path $RepositoryRoot $item.Value
        if(-not(Test-Path -LiteralPath $source -PathType Leaf)){Write-Warning "Source missing, skipped: $($item.Value)";continue}
        $destination=Join-Path $WorkingDirectory $item.Key
        if($PSCmdlet.ShouldProcess($destination,"Copy from $($item.Value)")){Copy-Item -LiteralPath $source -Destination $destination -Force;$written.Add($item.Key)}
    }
    $sidebar=Join-Path $WorkingDirectory '_Sidebar.md'
    $footer=Join-Path $WorkingDirectory '_Footer.md'
    if($PSCmdlet.ShouldProcess($sidebar,'Generate wiki sidebar')){Set-Content -LiteralPath $sidebar -Value (New-WikiNavigationContent -Pages $written.ToArray()) -Encoding utf8;$written.Add('_Sidebar.md')}
    if($PSCmdlet.ShouldProcess($footer,'Generate wiki footer')){Set-Content -LiteralPath $footer -Value "---`nSource repository: https://github.com/$($Configuration.Repository)`nGenerated by Initialize-GitHubRepositoryWiki.ps1`n" -Encoding utf8;$written.Add('_Footer.md')}
    $written
}
function Publish-WikiChanges{
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([Parameter(Mandatory)][string]$WorkingDirectory,[Parameter(Mandatory)][bool]$Push)
    Push-Location $WorkingDirectory
    try{
        & git add --all
        $status=& git status --porcelain
        if(-not $status){return [pscustomobject]@{Changed=$false;Committed=$false;Pushed=$false;Detail='No wiki changes detected'}}
        if($PSCmdlet.ShouldProcess($WorkingDirectory,'Commit wiki changes')){
            & git commit -m "Sync wiki from repository documentation"
            if($LASTEXITCODE -ne 0){throw 'Git commit failed.'}
        }
        $pushed=$false
        if($Push){if($PSCmdlet.ShouldProcess('origin','Push wiki changes')){& git push origin HEAD;if($LASTEXITCODE -ne 0){throw 'Git push failed.'};$pushed=$true}}
        [pscustomobject]@{Changed=$true;Committed=$true;Pushed=$pushed;Detail=$(if($Push){'Wiki changes committed and pushed'}else{'Wiki changes committed locally; use -Push to publish'})}
    }finally{Pop-Location}
}
function Invoke-GitHubRepositoryWiki{
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Settings)
    if(-not(Test-GitCommand)){throw 'git executable not found in PATH.'}
    $wikiUrl=Get-GitHubWikiUrl -Repository $Settings.Repository
    $sources=@(Get-WikiSourceStatus -RepositoryRoot $Settings.RepositoryRoot -SourceMap $Settings.SourceMap)
    $audit=[pscustomobject]@{Mode=$Settings.Mode;Repository=$Settings.Repository;WikiUrl=$wikiUrl;RepositoryRoot=$Settings.RepositoryRoot;WorkingDirectory=$Settings.WorkingDirectory;GitAvailable=$true;SourceCount=$sources.Count;MissingSources=@($sources|Where-Object{-not $_.Exists}).Count;PushRequested=$Settings.Push}
    $audit
    $sources
    if($Settings.Mode -eq 'Audit'){return}
    Initialize-WikiWorkingCopy -WikiUrl $wikiUrl -WorkingDirectory $Settings.WorkingDirectory -Mode $Settings.Mode -WhatIf:$WhatIfPreference
    $pages=@(Copy-WikiSources -RepositoryRoot $Settings.RepositoryRoot -WorkingDirectory $Settings.WorkingDirectory -SourceMap $Settings.SourceMap -WhatIf:$WhatIfPreference)
    $result=Publish-WikiChanges -WorkingDirectory $Settings.WorkingDirectory -Push ([bool]$Settings.Push) -WhatIf:$WhatIfPreference
    [pscustomobject]@{Mode=$Settings.Mode;Pages=$pages;Changed=$result.Changed;Committed=$result.Committed;Pushed=$result.Pushed;Detail=$result.Detail}
    if(-not $Settings.KeepWorkingDirectory -and -not $WhatIfPreference -and (Test-Path -LiteralPath $Settings.WorkingDirectory)){Remove-Item -LiteralPath $Settings.WorkingDirectory -Recurse -Force}
}
Invoke-GitHubRepositoryWiki -Settings $Configuration -WhatIf:$WhatIfPreference
