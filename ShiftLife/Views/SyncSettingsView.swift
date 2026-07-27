import SwiftUI
import CloudKit

/// Settings for the prepared iCloud family sync. Off by default; enabling it
/// starts CloudSync (which only does anything once the iCloud capability is
/// active – see CLOUDKIT.md). Includes an "invite partner" flow via CKShare.
struct SyncSettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var preparing = false
    @State private var payload: SharePayload?
    @State private var shareError: String?

    var body: some View {
        Form {
            Section {
                Toggle("iCloud-Sync aktiv", isOn: syncBinding)
            } footer: {
                Text("Teilt euren Plan live über iCloud – du und deine Freundin seht denselben Kalender. Kein eigener Server, keine Kosten.")
            }

            if store.data.syncEnabled {
                Section {
                    Button {
                        invitePartner()
                    } label: {
                        HStack {
                            Label("Partner einladen", systemImage: "person.crop.circle.badge.plus")
                            if preparing { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(preparing)
                } footer: {
                    if let shareError {
                        Text(shareError).foregroundStyle(Theme.danger)
                    } else {
                        Text("Verschickt eine iCloud-Einladung. Die eingeladene Person nimmt sie auf ihrem iPhone an und sieht dann denselben Plan.")
                    }
                }
            }

            Section {
                Label("Vorbereitet – am Mac aktivieren", systemImage: "wrench.and.screwdriver")
                    .font(.subheadline)
                Text("Diese Funktion ist im Code fertig, muss aber einmalig in Xcode mit der iCloud-Berechtigung freigeschaltet werden. Bis dahin bleibt alles lokal auf dem Gerät.")
                    .font(.caption).foregroundStyle(Theme.subtleText)
            }
        }
        .navigationTitle("Familien-Sync")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $payload) { p in CloudShareSheet(share: p.share, container: p.container) }
    }

    private func invitePartner() {
        preparing = true
        shareError = nil
        Task {
            do {
                let (share, container) = try await CloudSync.shared.prepareShare()
                await MainActor.run {
                    preparing = false
                    payload = SharePayload(share: share, container: container)
                }
            } catch {
                await MainActor.run {
                    preparing = false
                    shareError = "Einladung konnte nicht vorbereitet werden. Ist iCloud aktiviert? (\(error.localizedDescription))"
                }
            }
        }
    }

    private var syncBinding: Binding<Bool> {
        Binding(
            get: { store.data.syncEnabled },
            set: { on in
                store.data.syncEnabled = on
                if on { CloudSync.shared.startIfEnabled(store) }
                else { CloudSync.shared.stop() }
            }
        )
    }
}

/// A prepared CKShare + its container, ready to present.
struct SharePayload: Identifiable {
    let id = UUID()
    let share: CKShare
    let container: CKContainer
}

/// Presents the system iCloud sharing sheet for an already-prepared share
/// (iOS 17+ initializer – no deprecated preparation handler).
struct CloudShareSheet: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        return controller
    }

    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}
}
