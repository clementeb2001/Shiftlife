import SwiftUI

/// Paste a duty-confirmation e-mail; ShiftLife detects the on-call periods and
/// enters them as Bereitschaft shifts. Works entirely on-device – nothing is
/// sent anywhere. Same parser as the Share Extension and the Shortcuts intent.
struct ImportDutyMailView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var blocks: [ShiftMailParser.DutyBlock] = []
    @State private var didParse = false
    @State private var resultInfo: String?

    var body: some View {
        Form {
            Section {
                TextEditor(text: $text)
                    .frame(minHeight: 140)
                    .font(.callout)
                    .onChange(of: text) { _, _ in didParse = false; resultInfo = nil }
            } header: {
                Text("Mail-Text einfügen")
            } footer: {
                Text("Kopiere den Text der Dienst-Bestätigung (mit Datum und „Début/Fin\") und füge ihn hier ein.")
            }

            Section {
                Button {
                    blocks = ShiftMailParser.parse(text)
                    didParse = true
                } label: {
                    Label("Dienste erkennen", systemImage: "text.viewfinder")
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if didParse {
                if blocks.isEmpty {
                    Section {
                        Label("Keine Dienste erkannt. Prüfe, ob Datum und Uhrzeit im Text stehen.",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                } else {
                    Section {
                        ForEach(blocks) { b in
                            HStack {
                                Image(systemName: "flame.fill").foregroundStyle(AppColor.red.color)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Self.dayLabel(b.start)).fontWeight(.medium)
                                    Text(Self.rangeLabel(b.start, b.end))
                                        .font(.caption).foregroundStyle(Theme.subtleText)
                                }
                            }
                        }
                    } header: {
                        Text("\(blocks.count) Bereitschaftsdienst\(blocks.count == 1 ? "" : "e") erkannt")
                    } footer: {
                        Text("Aufeinanderfolgende Stunden werden zu einem Dienst zusammengefasst.")
                    }

                    Section {
                        Button {
                            let n = store.importOnCallBlocks(blocks)
                            resultInfo = n == 0 ? "Bereits eingetragen." : "\(n) Dienst(e) eingetragen."
                        } label: {
                            Label("In den Plan eintragen", systemImage: "calendar.badge.plus")
                        }
                    } footer: {
                        if let resultInfo {
                            Text(resultInfo).foregroundStyle(Theme.brand)
                        }
                    }
                }
            }
        }
        .navigationTitle("Bereitschaft aus Mail")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if resultInfo != nil {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
        }
    }

    private static func dayLabel(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "de_DE"); f.dateFormat = "EEEE, d. MMMM yyyy"
        return f.string(from: d)
    }

    private static func rangeLabel(_ s: Date, _ e: Date) -> String {
        let day = DateFormatter(); day.locale = Locale(identifier: "de_DE"); day.dateFormat = "d.M."
        let tf = DateFormatter(); tf.locale = Locale(identifier: "de_DE"); tf.dateFormat = "HH:mm"
        let cal = Calendar.current
        let sameDay = cal.isDate(s, inSameDayAs: e)
        if sameDay {
            return "\(tf.string(from: s))–\(tf.string(from: e)) Uhr"
        }
        return "\(day.string(from: s)) \(tf.string(from: s)) → \(day.string(from: e)) \(tf.string(from: e))"
    }
}
