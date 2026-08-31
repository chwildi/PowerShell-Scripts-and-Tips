#requires -Version 7.0
<#
.SYNOPSIS
    Initialisiert oder synchronisiert das GitHub Wiki eines Repositorys aus versionierten Markdown-Quellen.
.DESCRIPTION
    Dieses kundenneutrale Skript verwaltet ein GitHub Wiki ueber dessen Git-Repository (<owner>/<repo>.wiki.git).
    Ohne Parameter wird ein sicherer Audit-Modus ausgefuehrt. Initialize und Sync muessen explizit gewaehlt werden.

    Das Skript erkennt den lokalen Repository-Stamm automatisch mit "git rev-parse --show-toplevel",
    wenn -RepositoryRoot nicht angegeben wurde. Fehlende Quelldateien werden nur protokolliert und
    fuehren nicht mehr zu einem Abbruch bei der Sidebar-Erstellung.
.NOTES
    Author  : Hubert Inderwildi
    Version : 1.0.1.0
    License : MIT
    PowerShell: 7+
#>
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Medium')]
param(
    [ValidateSet('Audit','Initialize','Sync')][string]$Mode,
    [string]$Repository,
    [string]$RepositoryRoot,
    [string]$WorkingDirectory,
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
    RepositoryRoot=$null
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
function Resolve-RepositoryRoot{
    [CmdletBinding()]
    param([string]$RepositoryRoot)
    if($RepositoryRoot){
        if(-not(Test-Path -LiteralPath $RepositoryRoot -PathType Container)){throw "RepositoryRoot does not exist: $RepositoryRoot"}
        return (Resolve-Path -LiteralPath $RepositoryRoot).Path
    }
    if(Test-GitCommand){
        $root=& git rev-parse --show-toplevel 2>$null
        if($LASTEXITCODE -eq 0 -and $root){return ([string]$root).Trim()}
    }
    throw 'RepositoryRoot could not be determined automatically. Run the script inside the local Git repository or specify -RepositoryRoot explicitly.'
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
    param([AllowEmptyCollection()][string[]]$Pages=@())
    $links=@($Pages|Where-Object{$_ -and $_ -notin @('_Sidebar.md','_Footer.md')}|ForEach-Object{"- [$(($_ -replace '\.md$','') -replace '-',' ')]($(($_ -replace '\.md$','')))"})
    if($links.Count -eq 0){return "# Navigation`n`n- [Home](Home)`n"}
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
    param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)][string]$WorkingDirectory,[Parameter(Mandatory)][System.Collections.IDictionary]$SourceMap,[Parameter(Mandatory)][string]$Repository)
    $written=[System.Collections.Generic.List[string]]::new()
    foreach($item in $SourceMap.GetEnumerator()){
        $source=Join-Path $RepositoryRoot $item.Value
        if(-not(Test-Path -LiteralPath $source -PathType Leaf)){Write-Warning "Source missing, skipped: $($item.Value)";continue}
        $destination=Join-Path $WorkingDirectory $item.Key
        if($PSCmdlet.ShouldProcess($destination,"Copy from $($item.Value)")){Copy-Item -LiteralPath $source -Destination $destination -Force;$written.Add($item.Key)}
    }
    if($written.Count -eq 0){
        $existing=@(Get-ChildItem -LiteralPath $WorkingDirectory -Filter '*.md' -File -ErrorAction SilentlyContinue|Where-Object{$_.Name -notin @('_Sidebar.md','_Footer.md')}|Select-Object -ExpandProperty Name)
        foreach($page in $existing){$written.Add($page)}
    }
    $sidebar=Join-Path $WorkingDirectory '_Sidebar.md'
    $footer=Join-Path $WorkingDirectory '_Footer.md'
    if($PSCmdlet.ShouldProcess($sidebar,'Generate wiki sidebar')){Set-Content -LiteralPath $sidebar -Value (New-WikiNavigationContent -Pages @($written)) -Encoding utf8;if(-not $written.Contains('_Sidebar.md')){$written.Add('_Sidebar.md')}}
    if($PSCmdlet.ShouldProcess($footer,'Generate wiki footer')){Set-Content -LiteralPath $footer -Value "---`nSource repository: https://github.com/$Repository`nGenerated by Initialize-GitHubRepositoryWiki.ps1`n" -Encoding utf8;if(-not $written.Contains('_Footer.md')){$written.Add('_Footer.md')}}
    $written.ToArray()
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
            & git commit -m 'Sync wiki from repository documentation'
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
    $Settings.RepositoryRoot=Resolve-RepositoryRoot -RepositoryRoot $Settings.RepositoryRoot
    $wikiUrl=Get-GitHubWikiUrl -Repository $Settings.Repository
    $sources=@(Get-WikiSourceStatus -RepositoryRoot $Settings.RepositoryRoot -SourceMap $Settings.SourceMap)
    $audit=[pscustomobject]@{Mode=$Settings.Mode;Repository=$Settings.Repository;WikiUrl=$wikiUrl;RepositoryRoot=$Settings.RepositoryRoot;WorkingDirectory=$Settings.WorkingDirectory;GitAvailable=$true;SourceCount=$sources.Count;MissingSources=@($sources|Where-Object{-not $_.Exists}).Count;PushRequested=$Settings.Push}
    $audit
    $sources
    if($Settings.Mode -eq 'Audit'){return}
    Initialize-WikiWorkingCopy -WikiUrl $wikiUrl -WorkingDirectory $Settings.WorkingDirectory -Mode $Settings.Mode -WhatIf:$WhatIfPreference
    $pages=@(Copy-WikiSources -RepositoryRoot $Settings.RepositoryRoot -WorkingDirectory $Settings.WorkingDirectory -SourceMap $Settings.SourceMap -Repository $Settings.Repository -WhatIf:$WhatIfPreference)
    $result=Publish-WikiChanges -WorkingDirectory $Settings.WorkingDirectory -Push ([bool]$Settings.Push) -WhatIf:$WhatIfPreference
    [pscustomobject]@{Mode=$Settings.Mode;Pages=$pages;Changed=$result.Changed;Committed=$result.Committed;Pushed=$result.Pushed;Detail=$result.Detail}
    if(-not $Settings.KeepWorkingDirectory -and -not $WhatIfPreference -and (Test-Path -LiteralPath $Settings.WorkingDirectory)){Remove-Item -LiteralPath $Settings.WorkingDirectory -Recurse -Force}
}
Invoke-GitHubRepositoryWiki -Settings $Configuration -WhatIf:$WhatIfPreference
