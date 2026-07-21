import SwiftUI

/// Fair paywall: the core value (finding common free time) is experienced BEFORE
/// buying. Premium unlocks family features, unlimited patterns, stats, export.
/// This MVP simulates the purchase locally (StoreKit integration is a later step).
struct PaywallView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var plan: Plan = .family

    enum Plan: String, CaseIterable, Identifiable {
        case single, family
        var id: String { rawValue }
        var title: String { self == .single ? "Premium Einzel" : "Premium Familie" }
        var price: String { self == .single ? "24,99 € / Jahr" : "49,99 € / Jahr" }
        var features: [String] {
            switch self {
            case .single:
                return ["Unbegrenzte Schichtmuster", "Statistiken", "Widgets", "Kalenderexport", "Cloud-Synchronisierung"]
            case .family:
                return ["Alles aus Einzel", "Partner & Familie verbinden", "Gemeinsame Zeit unbegrenzt", "Konflikterkennung", "Gemeinsame Aufgaben", "Später: Kinderprofile"]
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.l) {
                    VStack(spacing: Theme.Space.s) {
                        Image(systemName: "sparkles").font(.system(size: 44)).foregroundStyle(Theme.brand)
                        Text("Mehr gemeinsame Zeit").font(.title2.bold())
                        Text("Ihr habt gesehen, wie ShiftLife freie Fenster findet. Premium bringt Partner, Konflikte und Aufgaben zusammen.")
                            .font(.subheadline).multilineTextAlignment(.center)
                            .foregroundStyle(Theme.subtleText)
                    }
                    .padding(.top)

                    Picker("Plan", selection: $plan) {
                        ForEach(Plan.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Card {
                        VStack(alignment: .leading, spacing: Theme.Space.m) {
                            Text(plan.title).font(.headline)
                            Text(plan.price).font(.title3.bold()).foregroundStyle(Theme.brand)
                            ForEach(plan.features, id: \.self) { f in
                                Label(f, systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.primary)
                            }
                            Text("Jahresabo klar günstiger als 12 Monatszahlungen.")
                                .font(.caption).foregroundStyle(Theme.subtleText)
                        }
                    }

                    Button {
                        store.data.isPremium = true
                        dismiss()
                    } label: { Text("Jetzt freischalten") }
                        .buttonStyle(PrimaryButtonStyle())

                    Text("Simulierter Kauf in der Vorschau. Echte Abwicklung über StoreKit folgt.")
                        .font(.caption2).foregroundStyle(Theme.subtleText)
                        .multilineTextAlignment(.center)
                }
                .padding(Theme.Space.l)
            }
            .navigationTitle("Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Später") { dismiss() } } }
        }
    }
}
