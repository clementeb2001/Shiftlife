import SwiftUI

/// Confirmation UI shown inside the share sheet. Reuses the shared parser and
/// store, writing on-call shifts into the App Group container the app reads.
struct ShareRootView: View {
    let text: String
    var onDone: () -> Void
    var onCancel: () -> Void

    @State private var blocks: [ShiftMailParser.DutyBlock] = []
    @State private var done = false
    @State private var created = 0

    var body: some View {
        NavigationStack {
            List {
                if done {
                    Label(created == 0 ? "Dienste waren bereits eingetragen."
                                       : "\(created) Bereitschaftsdienst(e) eingetragen.",
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if blocks.isEmpty {
                    Label("Keine Dienstzeiten im geteilten Text gefunden.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                } else {
                    Section("Erkannte Bereitschaft") {
                        ForEach(blocks) { b in
                            HStack {
                                Image(systemName: "flame.fill").foregroundStyle(.red)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Self.day(b.start)).fontWeight(.medium)
                                    Text(Self.range(b.start, b.end))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("ShiftLife")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", action: onCancel)
                }
                if done {
                    ToolbarItem(placement: .confirmationAction) { Button("Fertig", action: onDone) }
                } else if !blocks.isEmpty {
                    ToolbarItem(placement: .confirmationAction) { Button("Eintragen") { importIt() } }
                }
            }
            .onAppear { blocks = ShiftMailParser.parse(text) }
        }
    }

    private func importIt() {
        let store = AppStore()
        created = store.importOnCallBlocks(blocks)
        store.flush()
        done = true
    }

    private static func day(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "de_DE"); f.dateFormat = "EEEE, d. MMMM yyyy"
        return f.string(from: d)
    }
    private static func range(_ s: Date, _ e: Date) -> String {
        let tf = DateFormatter(); tf.locale = Locale(identifier: "de_DE"); tf.dateFormat = "HH:mm"
        let dl = DateFormatter(); dl.locale = Locale(identifier: "de_DE"); dl.dateFormat = "d.M."
        if Calendar.current.isDate(s, inSameDayAs: e) {
            return "\(tf.string(from: s))–\(tf.string(from: e)) Uhr"
        }
        return "\(dl.string(from: s)) \(tf.string(from: s)) → \(dl.string(from: e)) \(tf.string(from: e))"
    }
}
