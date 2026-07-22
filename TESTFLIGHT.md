# ShiftLife → iPhone / TestFlight

So bringst du ShiftLife auf dein echtes iPhone und zu deiner Freundin – Schritt
für Schritt. Aufgeteilt in **jetzt schon möglich (ohne Mac)** und **wenn du am
Mac bist**.

Der Weg ist bewusst der **einfachste**: erster Upload direkt über **Xcode**
(„Distribute App → TestFlight"), mit **automatischer Signierung**. Kein
Zertifikate-Basteln, keine CI-Geheimnisse nötig.

---

## Teil A — Jetzt schon erledigen (Urlaub, kein Mac nötig)

Das kannst du bequem am iPhone/im Browser vorbereiten. Manches (Freischaltung)
dauert 24–48 h, also ruhig jetzt starten.

1. **Apple Developer Program beitreten** (Pflicht für TestFlight, 99 €/Jahr)
   - <https://developer.apple.com/programs/enroll/>
   - Mit deiner normalen Apple-ID anmelden. Für eine Einzelperson „Individual"
     wählen (kein Firmen-D-U-N-S nötig).
   - Apple prüft und schaltet frei – das kann **1–2 Tage** dauern. Deshalb zuerst.
   - Aktiviere für die Apple-ID **Zwei-Faktor-Authentifizierung** (wird verlangt).

2. **Merke dir deine Team ID** (brauchst du am Mac)
   - Nach Freischaltung: <https://developer.apple.com/account> → „Membership".
   - Dort steht die **Team ID** (10 Zeichen, z. B. `A1B2C3D4E5`).

3. **App-Eintrag in App Store Connect anlegen** (geht im Browser)
   - <https://appstoreconnect.apple.com> → **Apps** → **+** → **Neue App**.
   - Plattform: iOS · Name: `ShiftLife` · Sprache: Deutsch
   - **Bundle-ID:** `com.shiftlife.app` auswählen.
     *Falls die ID belegt/nicht wählbar ist* → siehe Abschnitt
     „Bundle-ID ändern" unten. Dann hier die neue ID nehmen.
   - SKU: irgendein eindeutiges Kürzel, z. B. `shiftlife-001`.
   - (Screenshots/Beschreibung brauchst du für **TestFlight** noch nicht –
     nur für den späteren Store-Release.)

Mehr ist ohne Mac nicht sinnvoll. Der Rest passiert in Xcode.

---

## Teil B — Wenn du am (neuen) Mac bist

Dauer: ~30–60 Min. beim ersten Mal.

### 1. Vorbereitung
- **Xcode** aus dem Mac App Store installieren (aktuelle Version).
- Repo klonen bzw. den Branch `claude/ios-app-development-88wtpb` auschecken.
- `ShiftLife.xcodeproj` in Xcode öffnen.
- In Xcode oben mit deiner **Apple-ID** anmelden:
  Xcode → Settings → Accounts → **+** → Apple ID.

### 2. Signierung einstellen (für alle 3 Targets)
Für **jedes** der drei Targets – **ShiftLife**, **ShiftLifeWidgetExtension**,
**ShiftLifeShareExtension** – im Projekt-Editor unter
**Signing & Capabilities**:
- **Automatically manage signing** anhaken.
- **Team**: dein Developer-Team auswählen.
- Xcode legt dann Zertifikat + Provisioning-Profile automatisch an.

Die **App-Groups-Capability** (`group.com.shiftlife.app`) ist bereits im Projekt
hinterlegt und erscheint automatisch. Xcode registriert die Gruppe beim ersten
Signieren. Prüfe nur, dass bei allen drei Targets derselbe App-Group-Haken
gesetzt ist – das ist die Voraussetzung, damit **Widget** und
**„Teilen → ShiftLife"** die Daten der App sehen.

> Wenn Xcode meckert „Failed to register bundle identifier": meist ist die
> Bundle-ID schon vergeben → Abschnitt „Bundle-ID ändern".

### 3. Auf dem eigenen iPhone testen (optional, aber empfohlen)
- iPhone per Kabel anschließen, oben als Ziel-Gerät wählen.
- **Run** (▶). Beim ersten Mal am iPhone unter
  *Einstellungen → Allgemein → VPN & Geräteverwaltung* deinem Entwickler-Zertifikat
  vertrauen.
- Jetzt kannst du Widget (Home-Bildschirm → lange drücken → **+** → ShiftLife)
  und „Teilen → ShiftLife" direkt ausprobieren.

### 4. Archiv bauen & zu TestFlight hochladen
- Ziel oben auf **„Any iOS Device (arm64)"** stellen (nicht Simulator).
- Menü **Product → Archive**. Nach dem Build öffnet sich der **Organizer**.
- Archiv auswählen → **Distribute App** → **TestFlight (& App Store Connect)** →
  **Upload** → die Vorgaben durchklicken (automatische Signierung) → **Upload**.
- Nach ein paar Minuten erscheint der Build in App Store Connect unter
  **TestFlight**. Apple macht eine kurze automatische Prüfung („Processing").

### 5. Freundin als Testerin einladen
- **Interne Tester** (am schnellsten, bis zu 100 Personen, keine Apple-Review):
  App Store Connect → deine App → **TestFlight** → **Internal Testing** →
  Gruppe anlegen → Tester über ihre Apple-ID/E-Mail hinzufügen → Build zuweisen.
  *Hinweis:* interne Tester müssen in App Store Connect als „Benutzer" mit
  Rolle hinzugefügt sein.
- **Externe Tester** (einfacher per Link, aber erste Version braucht eine kurze
  **Beta-App-Review** von Apple, meist < 1 Tag): **External Testing** → Gruppe →
  öffentlichen Link teilen oder E-Mail einladen.
- Ihr installiert beide die **TestFlight-App** aus dem App Store und öffnet die
  Einladung → ShiftLife installieren. Builds laufen 90 Tage.

Fertig – ShiftLife läuft dann „echt" auf beiden iPhones. 🎉

---

## Bundle-ID ändern (nur falls `com.shiftlife.app` belegt ist)

Bundle-IDs sind weltweit eindeutig. Falls vergeben, nimm etwas Persönliches,
z. B. `com.deinname.shiftlife`. **Konsistent** an diesen Stellen ändern
(Suchen & Ersetzen):

- `ShiftLife.xcodeproj/project.pbxproj`
  - `com.shiftlife.app` → `com.deinname.shiftlife` (App, 2×)
  - `com.shiftlife.app.widget` → `com.deinname.shiftlife.widget` (2×)
  - `com.shiftlife.app.share` → `com.deinname.shiftlife.share` (2×)

Die **App-Group** kannst du bei `group.com.shiftlife.app` belassen (muss nur zu
deinem Team gehören). Wenn du sie doch änderst, dann an **allen** diesen Stellen
gleich:
- `ShiftLife/ShiftLife.entitlements`
- `ShiftLifeWidget/ShiftLifeWidget.entitlements`
- `ShiftLifeShareExtension/ShiftLifeShareExtension.entitlements`
- `ShiftLifeShared/SharedContainer.swift` (Konstante `appGroupID`)

---

## Häufige Stolpersteine

- **„No account for team" / „Signing requires a development team"** → Team bei
  allen drei Targets setzen (Schritt B.2).
- **„Failed to register bundle identifier"** → Bundle-ID schon vergeben →
  Abschnitt „Bundle-ID ändern".
- **App Group greift nicht (Widget bleibt leer)** → bei allen drei Targets muss
  dieselbe App-Group aktiviert sein; App einmal starten, damit sie Daten in den
  geteilten Speicher schreibt, dann Widget neu laden.
- **Build-Nummer schon vorhanden** → in den Target-Einstellungen
  `CURRENT_PROJECT_VERSION` (Build) hochzählen; `MARKETING_VERSION` (z. B. 1.0)
  bleibt gleich.

---

## Wie geht es dann weiter?

1. **Zusammen nutzen mit einem Datenstand pro Gerät (jetzt sofort möglich)**
   Aktuell sind die Daten lokal je Gerät. Zum Teilen eines Stands gibt es in den
   Einstellungen **Snapshot exportieren/importieren** (bzw. den .ics-Export).
   Gut zum Ausprobieren zu zweit.

2. **Echtes Live-Teilen (empfohlener nächster Ausbau): iCloud/CloudKit**
   Damit du und deine Freundin **denselben** Plan seht und Änderungen live
   synchronisiert werden, ohne eigenen Server. Die App ist dafür schon
   vorbereitet (`PersistenceProvider`-Schnittstelle, Details in `CLOUDKIT.md`).
   Das ist der logische Schritt nach dem ersten TestFlight-Test – sag Bescheid,
   dann baue ich `CloudKitPersistence` ein und aktiviere iCloud-Sync.

3. **Automatischer TestFlight-Upload aus der Cloud (optional, später)**
   Sobald das Developer-Konto steht, kann ich eine GitHub-Actions-Pipeline
   ergänzen, die bei jedem Push automatisch baut und zu TestFlight hochlädt
   (mit App-Store-Connect-API-Key als Secret). Praktisch für laufende Updates –
   für den **ersten** Upload ist der Xcode-Weg oben aber einfacher.

4. **Später: Veröffentlichung im App Store**
   Wenn ihr zufrieden seid: Screenshots, Beschreibung, Datenschutz-Angaben und
   App-Review. Das heben wir uns bewusst für den Schluss auf.
