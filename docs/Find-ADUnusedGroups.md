# Find-ADUnusedGroups

## Zweck

`Find-ADUnusedGroups.ps1` unterstützt Administratoren dabei, Active-Directory-Gruppen zu identifizieren, die möglicherweise nicht mehr verwendet werden. Das Skript arbeitet ausschließlich lesend und führt keine Änderungen oder Löschungen im Active Directory durch.

**Version:** 1.0.0.1

## Sicherheitsprinzip

Eine leere oder lange nicht geänderte AD-Gruppe ist nicht automatisch ungenutzt. Gruppen können weiterhin für LAPS, AD-Delegationen, GPOs, verschachtelte Gruppen oder Datei-/SMB-Berechtigungen benötigt werden.

Deshalb gilt für Version 1:

`READ -> ANALYZE -> EXPORT -> RECOMMEND`

Es werden keine Gruppen automatisch gelöscht oder verändert.

## Analysierte Nutzungssignale

Das Skript berücksichtigt insbesondere:

- direkte Gruppenmitglieder
- rekursive Gruppenmitglieder
- Mitgliedschaft der Gruppe in anderen Gruppen
- Erstellungsdatum und letzte AD-Änderung
- Windows-LAPS- und Legacy-LAPS-Nutzung
- AD-Delegationen und ACL-Referenzen
- GPO-Referenzen
- optional SMB-Share-Berechtigungen
- SID-basierte Referenzen, soweit durch die aktivierten Prüfungen ermittelbar

## Bewertung

Gruppen werden nicht nur als benutzt oder unbenutzt markiert. Die Analyse verwendet mehrere Kategorien:

- `ACTIVE` – eindeutige Nutzungssignale vorhanden
- `PROTECTED` – sicherheitsrelevante Verwendung erkannt, beispielsweise LAPS oder AD-Delegation
- `REVIEW` – manuelle Prüfung erforderlich
- `LIKELY_UNUSED` – mehrere Hinweise auf fehlende Nutzung
- `ORPHAN_CANDIDATE` – starker Kandidat für eine spätere kontrollierte Bereinigung

Zusätzlich wird ein `UnusedScore` verwendet, um mehrere Signale zusammenzuführen.

## Konfiguration

Das Skript besitzt am Anfang einen klar gekennzeichneten Configuration Block. Es kann ohne Parameter mit sicheren Standardwerten ausgeführt werden. Optionale Parameter können Konfigurationswerte überschreiben.

Wichtige Einstellungen umfassen unter anderem:

- SearchBase
- ausgeschlossene bzw. geschützte Gruppen
- InactiveDays
- OrphanCandidateDays
- Prüfung verschachtelter Gruppen
- AD-Delegationsprüfung
- LAPS-Prüfung
- GPO-Prüfung
- optionale SMB-/NTFS-Prüfungen
- Exportverzeichnis

## Ausgabe

Die Analyse erzeugt je nach Konfiguration unter anderem:

- `AD-Group-Inventory.csv`
- `AD-Group-Review.csv`
- `AD-Orphan-Candidates.csv`
- `AD-Protected-Groups.csv`
- `AD-Group-Analysis-Summary.txt`
- Log- und Transcript-Dateien

## Test

Zum Skript gehört ein separates Testskript:

`Find-ADUnusedGroups-TEST.ps1`

Dieses prüft unter anderem grundlegende Sicherheits- und Qualitätsanforderungen. PSScriptAnalyzer soll vor einer Veröffentlichung eingesetzt werden, sofern er auf dem Testsystem installiert ist.

Empfohlener erster Aufruf:

```powershell
pwsh.exe -File .\Find-ADUnusedGroups-TEST.ps1
```

Anschließend kann das eigentliche Analyseskript gestartet werden:

```powershell
pwsh.exe -File .\Find-ADUnusedGroups.ps1
```

## Voraussetzungen

- Windows-System mit Zugriff auf Active Directory
- PowerShell 7 für den vorgesehenen Projektstandard
- ActiveDirectory-Modul / RSAT
- für LAPS-Prüfungen die entsprechenden Windows-LAPS-Komponenten/Cmdlets
- ausreichende Leseberechtigungen für die zu untersuchenden AD-Objekte und ACLs

## Empfohlener Workflow

1. Testskript ausführen.
2. PSScriptAnalyzer-Ergebnis prüfen.
3. Analyse gegen eine geeignete AD-Umgebung ausführen.
4. Summary und CSV-Berichte kontrollieren.
5. `PROTECTED`-Gruppen niemals allein aufgrund fehlender Mitglieder bereinigen.
6. `REVIEW`, `LIKELY_UNUSED` und `ORPHAN_CANDIDATE` fachlich mit System- und Applikationsverantwortlichen prüfen.
7. Erst nach dokumentierter Freigabe eine getrennte Cleanup-Lösung verwenden.

## Geplante Weiterentwicklung

Das Skript ist für eine spätere Modularisierung vorbereitet. Geeignete öffentliche Funktionen eines gemeinsamen Moduls wären beispielsweise:

- `Get-ADGroupUsage`
- `Get-ADGroupUsageScore`
- `Find-ADUnusedGroup`

ACL-, LAPS-, GPO- und SID-Hilfsfunktionen sollten dabei überwiegend als interne Modul-Funktionen geführt werden.

Eine spätere Cleanup-Version sollte strikt getrennt bleiben und Schutzmechanismen wie `-WhatIf`, Freigabelisten, Protokollierung und explizite Bestätigung verwenden.
