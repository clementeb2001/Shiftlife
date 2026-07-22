# Zwei-Personen-Sharing: CloudKit-Aktivierungsplan

Ziel: ShiftLife zuerst **allein** nutzen, dann **mit Partner:in live teilen**, später
**veröffentlichen** – ohne Umbau, nur durch Aktivieren.

Die App ist bereits **CloudKit-ready** gebaut:

- Der gesamte Zustand liegt in `AppData` (reine `Codable`-Werte mit stabilen `UUID`s) –
  1:1 auf CloudKit-Records abbildbar.
- Persistenz läuft hinter dem Protokoll **`PersistenceProvider`**
  (`ShiftLife/Store/PersistenceProvider.swift`). Heute: `LocalJSONPersistence`
  (alles lokal, kein Konto). Später: `CloudKitPersistence` – **gleiche Schnittstelle**.
- `AppStore(persistence:)` nimmt den Provider im Initializer entgegen; nichts anderes
  im Code muss sich ändern.

## Was „live teilen" kostet

Ein **Apple Developer Program**-Account (99 €/Jahr). Der schaltet **beides** frei:
1. **TestFlight** – die App legal auf dem iPhone der Partnerin installieren (bis 100 Tester).
2. **CloudKit** – geteilte Daten zwischen zwei Geräten **ohne eigenen Server**
   (Apple-Infrastruktur, EU-Rechenzentren möglich, DSGVO-freundlich).

Solange kein Account da ist: Prototyp + Snapshot-Export/Import zum Testen genügen.

## Aktivierung (wenn der Account da ist)

1. **Capability hinzufügen:** In Xcode Target → *Signing & Capabilities* →
   **iCloud** → *CloudKit* aktivieren, Container `iCloud.com.shiftlife.app` anlegen.
2. **`CloudKitPersistence` implementieren** (neuer Typ, konform zu `PersistenceProvider`):
   - Empfehlung: **NSPersistentCloudKitContainer** oder eine schlanke eigene
     `CKRecord`-Zuordnung pro Entität (User, ShiftType, ShiftInstance, CalendarEvent,
     Task, Pickup …).
   - Ein **shared CloudKit-Zone** (`CKShare`) repräsentiert den Haushalt; die Partnerin
     tritt per Share-Link bei. Das ist der native Ersatz für den früheren
     „Einladungscode".
3. **Provider einstecken:** in `ShiftLifeApp`
   `AppStore(persistence: CloudKitPersistence())` statt Default.
4. **Konfliktauflösung:** Bei gleichzeitigem Bearbeiten „last-writer-wins" pro Feld
   genügt für den MVP; die Engine rechnet ohnehin lokal aus dem synchronisierten Stand.
5. **Rollen/Sichtbarkeit:** `Visibility` (privat / Partner / Haushalt) bleibt wie im
   Datenmodell; beim Sharing nur freigegebene Datensätze in die shared Zone schreiben.

## Danach: Veröffentlichung (App Store)

Gleicher Apple-Account. Schritte: App-Store-Connect-Eintrag, Datenschutzerklärung,
App-Privacy-Angaben (nur Planungsdaten, keine Diagnosedaten), Screenshots, Review.
Erst sinnvoll, wenn ihr die App im echten Alltag „gudd" findet – genau die
Reihenfolge aus dem Konzept (erst validieren, dann veröffentlichen).

## Bewusst noch NICHT umgesetzt

Kein eigener Server, kein Fremd-Backend, keine Standortdaten, keine dienstlichen
Inhalte. CloudKit hält Daten in Apples Ökosystem – minimaler Betriebsaufwand,
keine laufenden Serverkosten.
