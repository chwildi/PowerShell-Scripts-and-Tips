# Migriere-WindowsBenutzer

Kundenneutrales PowerShell-7-Werkzeug zum Sichern und Wiederherstellen lokaler Windows-Benutzerdaten bei Client- oder Domaenenmigrationen.

## Sicherheit

Ohne Parameter startet das Skript ausschliesslich im `Audit`-Modus und veraendert keine Daten. Export und Import muessen explizit gewaehlt werden. WLAN-Profile sind standardmaessig deaktiviert; ein Export mit Klartext-Schluesseln benoetigt sowohl `-IncludeWifiProfiles` als auch `-AllowClearTextWifiKeys`.

Das Skript migriert keine Kennwoerter, Credential-Manager-Eintraege, privaten Zertifikatschluessel oder Outlook-OST-Dateien.

## Voraussetzungen

- Windows
- PowerShell 7 oder neuer
- `robocopy.exe` fuer Export und Import
- Fuer die Qualitaetspruefung wird PSScriptAnalyzer empfohlen

## Verwendung

Sicherer Audit ohne Aenderungen:

```powershell
.\Migriere-WindowsBenutzer.ps1
```

Export zuerst simulieren:

```powershell
.\Migriere-WindowsBenutzer.ps1 -Mode Export -WhatIf
```

Export ausfuehren:

```powershell
.\Migriere-WindowsBenutzer.ps1 -Mode Export
```

Import zuerst simulieren:

```powershell
.\Migriere-WindowsBenutzer.ps1 -Mode Import -WhatIf
```

## Tests

```powershell
.\Tests\Migration\Migriere-WindowsBenutzer-TEST.ps1
```

Strenge Pruefung mit verpflichtendem PSScriptAnalyzer:

```powershell
.\Tests\Migration\Migriere-WindowsBenutzer-TEST.ps1 -RequirePSScriptAnalyzer
```

## Projektstandard

- Configuration Block mit sicheren Defaults
- Parameter sind optional und ueberschreiben die Konfiguration
- PowerShell 7+
- `SupportsShouldProcess` / `-WhatIf`
- separates `-TEST.ps1`
- keine kundenspezifischen Domains oder Geheimnisse im Repository
- MIT-Lizenz

## Version

`2.0.0.0`

## Lizenz

MIT. Siehe die zentrale `LICENSE`-Datei des Repositorys.
