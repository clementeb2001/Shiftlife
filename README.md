# ShiftLife (iOS · SwiftUI)

**Der gemeinsame Lebensplaner für Schichtarbeit, Partnerschaft und Familie.**

> Die Familienplanung richtet sich nach den Schichten – nicht umgekehrt.

ShiftLife verbindet persönliche Schichtpläne mit einem Familienkalender, gemeinsamen
Aufgaben und der **automatischen Erkennung gemeinsamer freier Zeit**. Diese Umsetzung
ist ein funktionsfähiger **MVP** auf Basis des beiliegenden Produktkonzepts.

Die App ist **native iOS-App mit SwiftUI** (die im Konzept bevorzugte Technik) und
läuft als **lokale, offline-fähige Vorschau** – ganz ohne Backend. Das Datenmodell ist
bewusst so geschnitten, dass es später 1:1 auf Server-Entitäten (Konten, Haushalt-Sync,
Push) abgebildet werden kann.

---

## Öffnen & Starten

1. **Xcode 16 oder neuer** öffnen (das Projekt nutzt synchronisierte Datei-Gruppen,
   `objectVersion = 77`).
2. `ShiftLife.xcodeproj` öffnen.
3. Schema **ShiftLife**, einen iOS-Simulator (z. B. iPhone 15) wählen und **⌘R**.

Beim ersten Start sind realistische Beispieldaten (Familie Berg: eine Schicht­arbeiterin,
ein Partner, ein Kind) geladen, damit alle Ansichten und die Berechnungslogik sofort
etwas zu zeigen haben.

> Es werden keinerlei Konten, Netzwerkzugriffe, Schlüssel oder Tracking benötigt.
> Alle Daten liegen lokal im App-Sandbox-Verzeichnis (`Documents/shiftlife_data.json`).

---

## Umgesetzte MVP-Funktionen

| # | Konzept-Anforderung | Umsetzung |
|---|---------------------|-----------|
| 1 | Konto / sicherer Haushalt | Onboarding + Haushalt mit Einladungscode (lokal) |
| 2 | Eigene Schichtarten | `ShiftType` inkl. Farbe, Zeiten, Ruhezeit, Kategorie |
| 3 | Wiederkehrende Schichtmuster | `ShiftPattern` + „Muster anwenden“ über Zeitraum |
| 4 | Einzelne Dienste ändern ohne Muster zu zerstören | Manuelle Overrides bleiben beim Re-Apply erhalten |
| 5 | Persönliche & gemeinsame Termine | `CalendarEvent` mit Sichtbarkeitsstufen |
| 6 | Partner / Familie einladen | Haushalt-Ansicht + Personen verwalten |
| 7 | **Automatische gemeinsame freie Zeit** | `CommonFreeTimeEngine` mit Filtern |
| 8 | Konflikterkennung | `ConflictEngine` mit konkreten Lösungsaktionen |
| 9 | Aufgaben & Zuweisung | `TaskItem` an Person oder Haushalt, mit Bedingungen |
| 10 | Push / Sync | Als spätere Backend-Schritte dokumentiert (siehe unten) |

### Hauptansichten (Tabs)
- **Heute** – dein Dienst, Verfügbarkeit aller, Konflikte, nächstes gemeinsames Fenster.
- **Woche** – mehrspurige Zeitleiste, eine Spur pro Person, auch bei 4–5 Personen lesbar.
- **Gemeinsam** – nächster gemeinsamer Abend, freie Tage, Suche nach Dauer/Tageszeit/Zeitraum.
- **Konflikte** – priorisierte Liste, jede Karte mit konkreter Handlung.
- **Aufgaben** – privat/gemeinsam, Zuständigkeit, Fälligkeit, Bedingungen.
- Zentraler **Schnell-hinzufügen**-Button (Dienst, Termin, Aufgabe, Urlaub, Verwaltung).

---

## Projektstruktur

```
ShiftLife/
├─ ShiftLifeApp.swift          App-Einstieg (Onboarding ↔ RootView)
├─ Models/Models.swift         Alle Entitäten (Codable)
├─ Store/
│  ├─ AppStore.swift           Zustand + lokale JSON-Persistenz, Export/Löschen
│  └─ SampleData.swift         Realistische Beispieldaten
├─ Engine/
│  ├─ TimeInterval+Busy.swift  Belegte Zeiträume (Schicht + Ruhezeit + Termine)
│  ├─ CommonFreeTimeEngine.swift  Erkennung gemeinsamer freier Zeit
│  └─ ConflictEngine.swift     Konfliktregeln (ohne Doppelwarnungen)
├─ DesignSystem/Theme.swift    Farben, Typo, Abstände, Komponenten
├─ Views/…                     Alle Ansichten (Heute, Woche, Gemeinsam, …)
└─ Assets.xcassets             App-Icon + Akzentfarbe (Light/Dark)

Tests/ShiftLifeEngineTests.swift  Unit-Tests der Kernlogik (siehe unten)
```

## Berechnungslogik (nachvollziehbar)

**Gemeinsame freie Zeit** (`CommonFreeTimeEngine`):
1. Für jede gewählte Person werden belegte Intervalle gesammelt: Schichten, optionale
   **Ruhezeit nach Nachtdienst** und Termine.
2. Alle belegten Intervalle werden zu einer gemeinsamen Belegungs-Zeitleiste verschmolzen.
3. Die Lücken dazwischen sind Kandidaten für freie Fenster.
4. Fenster werden auf die gewünschte Tageszeit zugeschnitten und pro Tag aufgeteilt.
5. Nur Fenster ≥ Mindestdauer bleiben; sortiert nach Startzeit, mit Begründung.

**Konflikte** (`ConflictEngine`): Termin ↔ Schicht, Termin direkt nach Nachtdienst,
Betreuung ohne verfügbare Person, „beide Eltern arbeiten“, Aufgabe ohne freie Person.
Jede (Art, Objekt, Zeitpunkt)-Kombination erzeugt höchstens **eine** Warnung.

## Design

Kleines Designsystem in `DesignSystem/Theme.swift`: ruhige, vertrauenswürdige Optik,
Karten, klare Zeitachsen, **Light & Dark Mode**. **Farbe ist nie die einzige
Information** – überall zusätzlich Beschriftung/Icon. Deutsche Oberfläche (Zielmarkt DACH/LU).

## Datenschutz

Datensparsamkeit: nur Planungsdaten, keine Dienst-/Patienten-/Falldaten. Alles bleibt
lokal. In den Einstellungen: **Datenexport (JSON)** und **vollständige Löschung**.

## Tests

`Tests/ShiftLifeEngineTests.swift` enthält Unit-Tests der Kernlogik. Sie sind absichtlich
**nicht** ins Projekt eingebunden, damit der App-Build auf einem frischen Checkout immer
sauber ist. Zum Ausführen in Xcode ein *Unit Testing Bundle* („ShiftLifeTests“) anlegen,
die Datei hineinziehen und **⌘U**.

## Bewusst nicht im MVP

Chat/Soziales, Standortverfolgung, medizinische Beratung, Lohnabrechnung, Diensttausch­börse,
Arbeitgeber-Dashboard, automatische Dienstplan-Erkennung aus Bild/PDF.

## Nächste (Backend-)Schritte

Sichere Authentifizierung, Haushalt-Synchronisierung (nahezu Echtzeit), Push über APNs,
StoreKit-Abos (die Paywall ist bereits enthalten und simuliert den Kauf), EU-konforme
Speicherung. Das lokale Datenmodell ist dafür vorbereitet.
