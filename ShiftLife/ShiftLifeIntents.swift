import AppIntents
import Foundation

/// Shortcuts / Siri entry point: hand ShiftLife the text of a duty-confirmation
/// mail and it enters the on-call periods. Lets the user automate capture — e.g.
/// a Mail rule or a "Run Shortcut" share action — without opening the app.
struct AddBereitschaftFromMailIntent: AppIntent {
    static var title: LocalizedStringResource = "Bereitschaft aus Mail eintragen"
    static var description = IntentDescription(
        "Erkennt Dienstzeiten im Text einer Bestätigungsmail und trägt sie als Bereitschaft in ShiftLife ein.")

    @Parameter(title: "Mail-Text")
    var mailText: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = AppStore()
        let blocks = ShiftMailParser.parse(mailText)
        let created = store.importOnCallBlocks(blocks)
        store.flush()

        let msg: String
        if blocks.isEmpty {
            msg = "Keine Dienstzeiten im Text gefunden."
        } else if created == 0 {
            msg = "Dienste waren bereits eingetragen."
        } else {
            msg = "\(created) Bereitschaftsdienst(e) eingetragen."
        }
        return .result(dialog: IntentDialog(stringLiteral: msg))
    }
}

struct ShiftLifeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddBereitschaftFromMailIntent(),
            phrases: [
                "Bereitschaft in \(.applicationName) eintragen",
                "Dienst in \(.applicationName) eintragen"
            ],
            shortTitle: "Bereitschaft eintragen",
            systemImageName: "flame.fill"
        )
    }
}
