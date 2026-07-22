import SwiftUI

/// Short value explanation → role choice → first shift in < 2 min → invite partner.
struct OnboardingView: View {
    @EnvironmentObject var store: AppStore
    @State private var page = 0
    @State private var name = ""
    @State private var role: MemberRole = .shiftWorker

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcome.tag(0)
                roleAndName.tag(1)
                firstShift.tag(2)
                invite.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
        .background(Theme.groupedBackground.ignoresSafeArea())
    }

    // MARK: Pages

    private var welcome: some View {
        VStack(spacing: Theme.Space.xl) {
            Spacer()
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 72))
                .foregroundStyle(Theme.brand)
            Text("ShiftLife")
                .font(.largeTitle.bold())
            Text("Der gemeinsame Lebensplaner für Schichtarbeit, Partnerschaft und Familie.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.subtleText)
            Text("Die Familienplanung richtet sich nach den Schichten – nicht umgekehrt.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
            Button("Los geht's") { withAnimation { page = 1 } }
                .buttonStyle(PrimaryButtonStyle())
            Spacer().frame(height: 40)
        }
        .padding(Theme.Space.xl)
    }

    private var roleAndName: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Text("Wer bist du?").font(.title.bold()).padding(.top, Theme.Space.xxl)
            Text("So passen wir die Ansichten für dich an.")
                .foregroundStyle(Theme.subtleText)

            TextField("Dein Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.title3)

            ForEach(MemberRole.allCases) { r in
                Button {
                    role = r
                } label: {
                    HStack {
                        Image(systemName: r.systemImage)
                            .frame(width: 28)
                        Text(r.label).fontWeight(.medium)
                        Spacer()
                        if role == r { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.brand) }
                    }
                    .padding()
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.chip)
                            .stroke(role == r ? Theme.brand : .clear, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
            }

            Spacer()
            Button("Weiter") { withAnimation { page = 2 } }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(Theme.Space.xl)
    }

    private var firstShift: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Text("Deine erste Schicht").font(.title.bold()).padding(.top, Theme.Space.xxl)
            Text("Wir haben typische Schichtarten schon vorbereitet – du kannst sie jederzeit ändern.")
                .foregroundStyle(Theme.subtleText)

            Card {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    ForEach(store.data.shiftTypes.prefix(4)) { t in
                        HStack {
                            Circle().fill(t.color.color).frame(width: 12, height: 12)
                            Text(t.name).fontWeight(.medium)
                            Spacer()
                            Text("\(t.startTimeString)–\(t.endTimeString)")
                                .font(.subheadline).foregroundStyle(Theme.subtleText)
                        }
                    }
                }
            }

            Label("Ein Muster (F-F-S-S-N-N-Frei) ist als Beispiel schon angelegt.",
                  systemImage: "sparkles")
                .font(.subheadline)
                .foregroundStyle(Theme.brand)

            Spacer()
            Button("Weiter") { withAnimation { page = 3 } }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(Theme.Space.xl)
    }

    private var invite: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Text("Deine Personen").font(.title.bold()).padding(.top, Theme.Space.xxl)
            Text("Lege Partner:in, Kinder oder weitere Personen als lokale Profile an. Nur so erkennt ShiftLife eure gemeinsame freie Zeit und Betreuungslücken. Alles bleibt auf diesem Gerät.")
                .foregroundStyle(Theme.subtleText)

            Card {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Label("Beispiel-Familie ist bereits angelegt", systemImage: "person.2.fill")
                        .font(.subheadline).fontWeight(.semibold)
                    Text("Du kannst Personen jederzeit unter „Meine Personen“ ergänzen oder ändern.")
                        .font(.caption).foregroundStyle(Theme.subtleText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
            Button("Fertig – App starten") {
                applyOnboarding()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(Theme.Space.xl)
    }

    private func applyOnboarding() {
        // Personalise the current user with the entered name/role.
        if let idx = store.data.members.firstIndex(where: { $0.isCurrentUser }) {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { store.data.members[idx].name = trimmed }
            store.data.members[idx].role = role
        }
        withAnimation { store.data.hasCompletedOnboarding = true }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.brand.opacity(configuration.isPressed ? 0.8 : 1))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
    }
}
