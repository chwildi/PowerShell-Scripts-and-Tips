#requires -Version 7.0
<#+
.SYNOPSIS
    Analysiert Active-Directory-Gruppen auf moegliche Nichtverwendung, ohne Aenderungen vorzunehmen.
.DESCRIPTION
    Version 1.0.0.1. Read-only Analyse fuer AD-Gruppen. Bewertet u. a. Mitglieder,
    Verschachtelung, Alter, AD-Delegationen, Windows/Legacy LAPS und GPO-Referenzen.
    Optional koennen SMB-Share-Berechtigungen geprueft werden.

    WICHTIG: Dieses Skript fuehrt keine Loesch-, Schreib- oder Bereinigungsaktionen im AD aus.
.NOTES
    PowerShell 7 kompatibel. Fuer AD-Abfragen wird das ActiveDirectory-Modul benoetigt.
    GPO-Pruefung benoetigt optional das GroupPolicy-Modul.
    Windows-LAPS-Pruefung nutzt optional das LAPS-Modul, falls vorhanden.
    Autor: OpenAI / Projektstandard
    Version: 1.0.0.1
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$SearchBase,

    [Parameter()]
    [ValidateRange(1,3650)]
    [int]$InactiveDays,

    [Parameter()]
    [ValidateRange(1,3650)]
    [int]$OrphanCandidateDays,

    [Parameter()]
    [string]$ExportPath,

    [Parameter()]
    [switch]$SkipADDelegations,

    [Parameter()]
    [switch]$SkipLAPS,

    [Parameter()]
    [switch]$SkipGPO,

    [Parameter()]
    [switch]$CheckSMBShares,

    [Parameter()]
    [string[]]$FileServers
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ============================================================
# CONFIGURATION BLOCK
# Sichere Standardwerte. Alle Werte koennen per Parameter
# ueberschrieben werden. Ein parameterloser Start ist moeglich.
# ============================================================
$Configuration = [ordered]@{
    SearchBase             = ''
    InactiveDays           = 365
    OrphanCandidateDays    = 730
    ExportPath             = 'D:\IT-Intern\05-Exporte\AD-Group-Analysis'
    CheckNestedGroups      = $true
    CheckADDelegations     = $true
    CheckLAPS              = $true
    CheckGPO               = $true
    CheckSMBShares         = $false
    FileServers            = @()
    ExcludedGroups         = @(
        'Administrators',
        'Domain Admins',
        'Enterprise Admins',
        'Schema Admins',
        'Domain Users',
        'Domain Computers',
        'Domain Controllers',
        'Group Policy Creator Owners',
        'Protected Users',
        'Enterprise Key Admins',
        'Key Admins'
    )
}

if ($PSBoundParameters.ContainsKey('SearchBase'))          { $Configuration.SearchBase = $SearchBase }
if ($PSBoundParameters.ContainsKey('InactiveDays'))        { $Configuration.InactiveDays = $InactiveDays }
if ($PSBoundParameters.ContainsKey('OrphanCandidateDays')) { $Configuration.OrphanCandidateDays = $OrphanCandidateDays }
if ($PSBoundParameters.ContainsKey('ExportPath'))          { $Configuration.ExportPath = $ExportPath }
if ($SkipADDelegations)                                    { $Configuration.CheckADDelegations = $false }
if ($SkipLAPS)                                             { $Configuration.CheckLAPS = $false }
if ($SkipGPO)                                              { $Configuration.CheckGPO = $false }
if ($CheckSMBShares)                                       { $Configuration.CheckSMBShares = $true }
if ($PSBoundParameters.ContainsKey('FileServers'))         { $Configuration.FileServers = @($FileServers) }

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Message,
        [ValidateSet('INFO','WARN','ERROR','OK')] [string]$Level = 'INFO'
    )
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line
    if ($script:LogFile) { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding utf8 }
}

function Test-RequiredModule {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$Name, [switch]$Optional)
    $module = Get-Module -ListAvailable -Name $Name | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $module) {
        if ($Optional) { Write-Log "Optionales Modul '$Name' nicht gefunden." 'WARN'; return $false }
        throw "Erforderliches Modul '$Name' wurde nicht gefunden."
    }
    Import-Module $Name -ErrorAction Stop
    return $true
}

function Resolve-PrincipalSid {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$IdentityReference)
    try {
        $nt = [System.Security.Principal.NTAccount]::new($IdentityReference)
        return $nt.Translate([System.Security.Principal.SecurityIdentifier]).Value
    } catch { return $null }
}

function Get-ADGroupMembershipSignal {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Group)

    $directMembers = @()
    $recursiveMembers = @()
    try { $directMembers = @(Get-ADGroupMember -Identity $Group.DistinguishedName -ErrorAction Stop) } catch { Write-Log "Direkte Mitglieder fuer '$($Group.Name)' nicht lesbar: $($_.Exception.Message)" 'WARN' }
    if ($Configuration.CheckNestedGroups) {
        try { $recursiveMembers = @(Get-ADGroupMember -Identity $Group.DistinguishedName -Recursive -ErrorAction Stop) } catch { Write-Log "Rekursive Mitglieder fuer '$($Group.Name)' nicht lesbar: $($_.Exception.Message)" 'WARN' }
    }

    [pscustomobject]@{
        DirectMemberCount    = $directMembers.Count
        RecursiveMemberCount = $recursiveMembers.Count
        DirectUsers          = @($directMembers | Where-Object objectClass -eq 'user').Count
        DirectComputers      = @($directMembers | Where-Object objectClass -eq 'computer').Count
        DirectGroups         = @($directMembers | Where-Object objectClass -eq 'group').Count
    }
}

function Get-ADDelegationReferences {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable]$SidToGroup)

    $hits = @{}
    foreach ($sid in $SidToGroup.Keys) { $hits[$sid] = [System.Collections.Generic.List[string]]::new() }

    $objects = [System.Collections.Generic.List[string]]::new()
    $domain = Get-ADDomain
    $objects.Add($domain.DistinguishedName)
    Get-ADOrganizationalUnit -Filter * -Properties DistinguishedName | ForEach-Object { $objects.Add($_.DistinguishedName) }

    foreach ($dn in $objects) {
        try {
            $acl = Get-Acl -Path ("AD:\{0}" -f $dn)
            foreach ($ace in $acl.Access) {
                $sid = Resolve-PrincipalSid -IdentityReference $ace.IdentityReference.Value
                if ($sid -and $hits.ContainsKey($sid)) {
                    $hits[$sid].Add("$dn | $($ace.ActiveDirectoryRights) | $($ace.AccessControlType)")
                }
            }
        } catch {
            Write-Log "ACL fuer '$dn' konnte nicht gelesen werden: $($_.Exception.Message)" 'WARN'
        }
    }
    return $hits
}

function Get-LapsReferences {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable]$SidToGroup)

    $hits = @{}
    foreach ($sid in $SidToGroup.Keys) { $hits[$sid] = [System.Collections.Generic.List[string]]::new() }

    $ous = @(Get-ADOrganizationalUnit -Filter * -Properties DistinguishedName)

    if (Get-Command Find-LapsADExtendedRights -ErrorAction SilentlyContinue) {
        foreach ($ou in $ous) {
            try {
                $entries = @(Find-LapsADExtendedRights -Identity $ou.DistinguishedName -ErrorAction Stop)
                foreach ($entry in $entries) {
                    foreach ($principal in @($entry.ExtendedRightHolders)) {
                        $sid = Resolve-PrincipalSid -IdentityReference ([string]$principal)
                        if ($sid -and $hits.ContainsKey($sid)) { $hits[$sid].Add("Windows LAPS | $($ou.DistinguishedName)") }
                    }
                }
            } catch { Write-Log "Windows-LAPS-Rechte fuer '$($ou.DistinguishedName)' nicht lesbar: $($_.Exception.Message)" 'WARN' }
        }
    }

    $lapsSchemaGuids = @{}
    try {
        $schemaNc = (Get-ADRootDSE).SchemaNamingContext
        $lapsAttributes = @(Get-ADObject -SearchBase $schemaNc -LDAPFilter '(|(lDAPDisplayName=ms-Mcs-AdmPwd)(lDAPDisplayName=ms-Mcs-AdmPwdExpirationTime)(lDAPDisplayName=msLAPS-Password)(lDAPDisplayName=msLAPS-EncryptedPassword)(lDAPDisplayName=msLAPS-PasswordExpirationTime))' -Properties lDAPDisplayName,schemaIDGUID)
        foreach ($attr in $lapsAttributes) {
            if ($attr.schemaIDGUID) {
                $guid = [guid]::new([byte[]]$attr.schemaIDGUID)
                $lapsSchemaGuids[$guid.Guid] = [string]$attr.lDAPDisplayName
            }
        }
    } catch { Write-Log "LAPS-Schemaattribute konnten nicht aufgeloest werden: $($_.Exception.Message)" 'WARN' }

    if ($lapsSchemaGuids.Count -gt 0) {
        foreach ($ou in $ous) {
            try {
                $acl = Get-Acl -Path ("AD:\{0}" -f $ou.DistinguishedName)
                foreach ($ace in $acl.Access) {
                    $sid = Resolve-PrincipalSid -IdentityReference $ace.IdentityReference.Value
                    if (-not ($sid -and $hits.ContainsKey($sid))) { continue }
                    $objectType = ([guid]$ace.ObjectType).Guid
                    if ($lapsSchemaGuids.ContainsKey($objectType)) {
                        $hits[$sid].Add("LAPS ACL | $($ou.DistinguishedName) | $($lapsSchemaGuids[$objectType]) | $($ace.ActiveDirectoryRights)")
                    }
                }
            } catch { Write-Log "LAPS-ACL fuer '$($ou.DistinguishedName)' nicht lesbar: $($_.Exception.Message)" 'WARN' }
        }
    }
    return $hits
}

function Get-GpoReferences {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable]$SidToGroup)

    $hits = @{}
    foreach ($sid in $SidToGroup.Keys) { $hits[$sid] = [System.Collections.Generic.List[string]]::new() }
    if (-not (Get-Command Get-GPO -ErrorAction SilentlyContinue)) { return $hits }

    foreach ($gpo in @(Get-GPO -All)) {
        try {
            $xml = Get-GPOReport -Guid $gpo.Id -ReportType Xml
            foreach ($sid in $SidToGroup.Keys) {
                $name = $SidToGroup[$sid].SamAccountName
                if ($xml -match [regex]::Escape($sid) -or $xml -match [regex]::Escape($name)) {
                    $hits[$sid].Add("GPO | $($gpo.DisplayName) | $($gpo.Id)")
                }
            }
        } catch { Write-Log "GPO '$($gpo.DisplayName)' konnte nicht analysiert werden: $($_.Exception.Message)" 'WARN' }
    }
    return $hits
}

function Get-SmbReferences {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable]$SidToGroup, [string[]]$Servers)

    $hits = @{}
    foreach ($sid in $SidToGroup.Keys) { $hits[$sid] = [System.Collections.Generic.List[string]]::new() }
    foreach ($server in $Servers) {
        try {
            $shares = Invoke-Command -ComputerName $server -ScriptBlock { Get-SmbShare | Where-Object Special -eq $false }
            foreach ($share in $shares) {
                $access = Invoke-Command -ComputerName $server -ArgumentList $share.Name -ScriptBlock { param($n) Get-SmbShareAccess -Name $n }
                foreach ($entry in $access) {
                    $sid = Resolve-PrincipalSid -IdentityReference $entry.AccountName
                    if ($sid -and $hits.ContainsKey($sid)) { $hits[$sid].Add("SMB | $server | $($share.Name) | $($entry.AccessRight)") }
                }
            }
        } catch { Write-Log "SMB-Pruefung auf '$server' fehlgeschlagen: $($_.Exception.Message)" 'WARN' }
    }
    return $hits
}

function Get-GroupClassification {
    [CmdletBinding()]
    param(
        [int]$DirectMembers,
        [int]$RecursiveMembers,
        [int]$MemberOfCount,
        [int]$DaysSinceModified,
        [bool]$HasLaps,
        [bool]$HasDelegation,
        [bool]$HasGpo,
        [bool]$HasSmb,
        [bool]$IsExcluded
    )

    if ($IsExcluded -or $HasLaps -or $HasDelegation) {
        return [pscustomobject]@{ Score = 0; Classification = 'PROTECTED'; DoNotDelete = $true }
    }

    $score = 0
    if ($DirectMembers -eq 0) { $score += 20 } else { $score -= 50 }
    if ($RecursiveMembers -eq 0) { $score += 5 }
    if ($MemberOfCount -eq 0) { $score += 15 } else { $score -= 30 }
    if ($DaysSinceModified -ge $Configuration.InactiveDays) { $score += 20 }
    if ($DaysSinceModified -ge $Configuration.OrphanCandidateDays) { $score += 20 }
    if (-not $HasGpo -and -not $HasSmb) { $score += 20 }
    if ($HasGpo) { $score -= 80 }
    if ($HasSmb) { $score -= 80 }
    $score = [Math]::Max(0,[Math]::Min(100,$score))

    $classification = if ($score -ge 75) { 'ORPHAN_CANDIDATE' }
        elseif ($score -ge 50) { 'LIKELY_UNUSED' }
        elseif ($score -ge 21) { 'REVIEW' }
        else { 'ACTIVE' }

    [pscustomobject]@{ Score = $score; Classification = $classification; DoNotDelete = $false }
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$runPath = Join-Path $Configuration.ExportPath $timestamp
New-Item -ItemType Directory -Path $runPath -Force | Out-Null
$script:LogFile = Join-Path $runPath "AD-Group-Analysis-$timestamp.log"
$transcript = Join-Path $runPath "AD-Group-Analysis-Transcript-$timestamp.txt"
Start-Transcript -Path $transcript -Force | Out-Null

try {
    Write-Log 'Starte AD-Gruppenanalyse Version 1.0.0.1.'
    Test-RequiredModule -Name ActiveDirectory | Out-Null
    if ($Configuration.CheckGPO) { Test-RequiredModule -Name GroupPolicy -Optional | Out-Null }
    if ($Configuration.CheckLAPS) { Test-RequiredModule -Name LAPS -Optional | Out-Null }

    $properties = @('whenCreated','whenChanged','memberOf','description','managedBy','adminCount','isCriticalSystemObject','ObjectSid')
    $groups = if ([string]::IsNullOrWhiteSpace($Configuration.SearchBase)) {
        @(Get-ADGroup -Filter * -Properties $properties)
    } else {
        @(Get-ADGroup -Filter * -SearchBase $Configuration.SearchBase -Properties $properties)
    }
    Write-Log ("{0} Gruppen geladen." -f $groups.Count) 'OK'

    $sidToGroup = @{}
    foreach ($g in $groups) { if ($g.SID) { $sidToGroup[$g.SID.Value] = $g } }

    $delegationHits = @{}
    if ($Configuration.CheckADDelegations) { Write-Log 'Pruefe AD-Delegationen...'; $delegationHits = Get-ADDelegationReferences -SidToGroup $sidToGroup }
    $lapsHits = @{}
    if ($Configuration.CheckLAPS) { Write-Log 'Pruefe LAPS-Verwendungen...'; $lapsHits = Get-LapsReferences -SidToGroup $sidToGroup }
    $gpoHits = @{}
    if ($Configuration.CheckGPO -and (Get-Command Get-GPO -ErrorAction SilentlyContinue)) { Write-Log 'Pruefe GPO-Referenzen...'; $gpoHits = Get-GpoReferences -SidToGroup $sidToGroup }
    $smbHits = @{}
    if ($Configuration.CheckSMBShares -and $Configuration.FileServers.Count -gt 0) { Write-Log 'Pruefe SMB-Share-Berechtigungen...'; $smbHits = Get-SmbReferences -SidToGroup $sidToGroup -Servers $Configuration.FileServers }

    $results = foreach ($group in $groups) {
        $membership = Get-ADGroupMembershipSignal -Group $group
        $sid = $group.SID.Value
        $memberOf = @($group.MemberOf)
        $days = [Math]::Floor(((Get-Date) - [datetime]$group.whenChanged).TotalDays)
        $deleg = if ($delegationHits.ContainsKey($sid)) { @($delegationHits[$sid]) } else { @() }
        $laps  = if ($lapsHits.ContainsKey($sid)) { @($lapsHits[$sid]) } else { @() }
        $gpo   = if ($gpoHits.ContainsKey($sid)) { @($gpoHits[$sid]) } else { @() }
        $smb   = if ($smbHits.ContainsKey($sid)) { @($smbHits[$sid]) } else { @() }
        $excluded = $Configuration.ExcludedGroups -contains $group.SamAccountName -or $Configuration.ExcludedGroups -contains $group.Name -or [bool]$group.isCriticalSystemObject

        $rating = Get-GroupClassification -DirectMembers $membership.DirectMemberCount -RecursiveMembers $membership.RecursiveMemberCount -MemberOfCount $memberOf.Count -DaysSinceModified $days -HasLaps ($laps.Count -gt 0) -HasDelegation ($deleg.Count -gt 0) -HasGpo ($gpo.Count -gt 0) -HasSmb ($smb.Count -gt 0) -IsExcluded $excluded
        $signals = [System.Collections.Generic.List[string]]::new()
        if ($membership.DirectMemberCount -gt 0) { $signals.Add('DirectMembers') }
        if ($memberOf.Count -gt 0) { $signals.Add('NestedInGroup') }
        if ($deleg.Count -gt 0) { $signals.Add('ADDelegation') }
        if ($laps.Count -gt 0) { $signals.Add('LAPS') }
        if ($gpo.Count -gt 0) { $signals.Add('GPO') }
        if ($smb.Count -gt 0) { $signals.Add('SMB') }
        if ($excluded) { $signals.Add('BuiltInOrExcluded') }

        [pscustomobject]@{
            Name                 = $group.Name
            SamAccountName       = $group.SamAccountName
            SID                  = $sid
            DistinguishedName    = $group.DistinguishedName
            GroupScope           = $group.GroupScope
            GroupCategory        = $group.GroupCategory
            Description          = $group.Description
            ManagedBy            = $group.ManagedBy
            Created              = $group.whenCreated
            Modified             = $group.whenChanged
            DaysSinceModified    = $days
            DirectMemberCount    = $membership.DirectMemberCount
            RecursiveMemberCount = $membership.RecursiveMemberCount
            DirectUsers          = $membership.DirectUsers
            DirectComputers      = $membership.DirectComputers
            DirectGroups         = $membership.DirectGroups
            MemberOfCount        = $memberOf.Count
            MemberOf             = ($memberOf -join '; ')
            LAPSUsage            = ($laps -join '; ')
            ADDelegationUsage    = ($deleg -join '; ')
            GPOUsage             = ($gpo -join '; ')
            SMBUsage             = ($smb -join '; ')
            UsageSignals         = ($signals -join '; ')
            UnusedScore          = $rating.Score
            Classification       = $rating.Classification
            DoNotDelete          = $rating.DoNotDelete
            ReviewReason         = if ($rating.Classification -in @('LIKELY_UNUSED','ORPHAN_CANDIDATE','REVIEW')) { "Score=$($rating.Score); keine automatische Loeschfreigabe" } else { '' }
        }
    }

    $inventoryFile = Join-Path $runPath "AD-Group-Inventory-$timestamp.csv"
    $reviewFile = Join-Path $runPath "AD-Group-Review-$timestamp.csv"
    $orphanFile = Join-Path $runPath "AD-Orphan-Candidates-$timestamp.csv"
    $protectedFile = Join-Path $runPath "AD-Protected-Groups-$timestamp.csv"
    $summaryFile = Join-Path $runPath "AD-Group-Analysis-Summary-$timestamp.txt"

    $results | Sort-Object Classification,UnusedScore -Descending | Export-Csv -Path $inventoryFile -NoTypeInformation -Encoding utf8BOM
    $results | Where-Object Classification -in @('REVIEW','LIKELY_UNUSED','ORPHAN_CANDIDATE') | Sort-Object UnusedScore -Descending | Export-Csv -Path $reviewFile -NoTypeInformation -Encoding utf8BOM
    $results | Where-Object Classification -eq 'ORPHAN_CANDIDATE' | Sort-Object UnusedScore -Descending | Export-Csv -Path $orphanFile -NoTypeInformation -Encoding utf8BOM
    $results | Where-Object { $_.DoNotDelete -or $_.Classification -eq 'PROTECTED' } | Export-Csv -Path $protectedFile -NoTypeInformation -Encoding utf8BOM

    $summary = @(
        'AD Group Analysis - Version 1.0.0.1',
        "Zeitpunkt: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "Domain: $((Get-ADDomain).DNSRoot)",
        "SearchBase: $($Configuration.SearchBase)",
        "Gruppen gesamt: $($results.Count)",
        "ACTIVE: $(@($results | Where-Object Classification -eq 'ACTIVE').Count)",
        "PROTECTED: $(@($results | Where-Object Classification -eq 'PROTECTED').Count)",
        "REVIEW: $(@($results | Where-Object Classification -eq 'REVIEW').Count)",
        "LIKELY_UNUSED: $(@($results | Where-Object Classification -eq 'LIKELY_UNUSED').Count)",
        "ORPHAN_CANDIDATE: $(@($results | Where-Object Classification -eq 'ORPHAN_CANDIDATE').Count)",
        '',
        'WICHTIG: ORPHAN_CANDIDATE ist nur eine Pruefempfehlung. Dieses Skript loescht oder veraendert keine Gruppen.'
    )
    Set-Content -Path $summaryFile -Value $summary -Encoding utf8

    Write-Log "Analyse abgeschlossen. Ausgabe: $runPath" 'OK'
    $results
}
catch {
    Write-Log "Kritischer Fehler: $($_.Exception.Message)" 'ERROR'
    throw
}
finally {
    try { Stop-Transcript | Out-Null } catch { }
}
