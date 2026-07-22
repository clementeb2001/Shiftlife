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

## Der Sync ist bereits IMPLEMENTIERT (nur ausgeschaltet)

Seit dem CloudKit-Vorbereitungs-Commit liegt die Synchronisation fertig im Code
und ist **standardmäßig aus** (`AppData.syncEnabled == false`), damit der erste
TestFlight-Upload einfach bleibt und die App bis zur Aktivierung 100 % lokal ist.

- `ShiftLifeShared/CloudSync.swift` – spiegelt den gesamten `AppData`-Stand als
  ein Record ("AppState") in einer eigenen Zone der **privaten** CloudKit-DB;
  die Zone wird per `CKShare` mit der Partnerin geteilt. Konfliktauflösung:
  last-writer-wins über `AppData.updatedAt`.
- `AppStore` ruft nach jeder lokalen Änderung `onLocalChange` → CloudSync pusht
  (entprellt). Beim Start / im Vordergrund wird `refresh()` gezogen.
- `Views/SyncSettingsView.swift` – Schalter „iCloud-Sync" + „Partner einladen"
  (System-Sharing-Sheet). Erreichbar über Einstellungen → „Familien-Sync".

## Aktivierung am Mac (wenn der Account da ist)

1. **Capability hinzufügen:** In Xcode für das App-Target → *Signing &
   Capabilities* → **+ Capability → iCloud** → Häkchen bei **CloudKit** →
   Container **`iCloud.com.shiftlife.app`** anlegen (exakt dieser Name, er steht
   so in `CloudSync.containerID`).
2. **Hintergrund-Push (für Live-Updates):** *+ Capability → Background Modes* →
   **Remote notifications** aktivieren (für die stille CloudKit-Subscription).
3. **Bauen & auf beide iPhones** (per TestFlight, siehe `TESTFLIGHT.md`).
4. **In der App:** Einstellungen → „Familien-Sync (iCloud)" → Schalter **an**,
   dann **„Partner einladen"** → iCloud-Einladung verschicken; die Partnerin
   nimmt sie auf ihrem iPhone an und sieht danach denselben Plan.

> Hinweis: CloudKit lässt sich **nur auf echten Geräten mit iCloud** testen –
> nicht im Simulator/CI. Der Code kompiliert dort sauber, der echte Sync-Ablauf
> muss beim ersten Aktivieren am Gerät verifiziert werden. Kleinere Feinheiten
> (Subscription-Handling, Annahme-Flow der Einladung) justieren wir dann live.

## Bekannte Härtung für später

Der `AppData`-Blob wird als Ganzes synchronisiert (einfach, robust für ein Paar).
Zwei Punkte fürs spätere Feilen, sobald echte Daten im Spiel sind:
- **Schema-Migration:** neue `Codable`-Felder tolerant dekodieren (sonst fällt ein
  alter Stand auf Beispieldaten zurück). Heute unkritisch, da noch keine Echtdaten.
- **Feingranulares Merge:** statt Blob-„last-writer-wins" pro Entität mergen, falls
  beide **gleichzeitig** offline viel ändern (für ein Paar selten relevant).

## Danach: Veröffentlichung (App Store)

Gleicher Apple-Account. Schritte: App-Store-Connect-Eintrag, Datenschutzerklärung,
App-Privacy-Angaben (nur Planungsdaten, keine Diagnosedaten), Screenshots, Review.
Erst sinnvoll, wenn ihr die App im echten Alltag „gudd" findet – genau die
Reihenfolge aus dem Konzept (erst validieren, dann veröffentlichen).

## Bewusst noch NICHT umgesetzt

Kein eigener Server, kein Fremd-Backend, keine Standortdaten, keine dienstlichen
Inhalte. CloudKit hält Daten in Apples Ökosystem – minimaler Betriebsaufwand,
keine laufenden Serverkosten.
