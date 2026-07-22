import SwiftUI
import CloudKit

/// Settings for the prepared iCloud family sync. Off by default; enabling it
/// starts CloudSync (which only does anything once the iCloud capability is
/// active – see CLOUDKIT.md). Includes a "invite partner" flow via CKShare.
struct SyncSettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var showShare = false

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
                        showShare = true
                    } label: {
                        Label("Partner einladen", systemImage: "person.crop.circle.badge.plus")
                    }
                } footer: {
                    Text("Verschickt eine iCloud-Einladung. Die eingeladene Person nimmt sie auf ihrem iPhone an und sieht dann denselben Plan.")
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
        .sheet(isPresented: $showShare) { CloudShareSheet() }
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

/// Presents the system iCloud sharing sheet for the sync zone.
struct CloudShareSheet: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController { _, completion in
            Task {
                do {
                    let (share, container) = try await CloudSync.shared.prepareShare()
                    completion(share, container, nil)
                } catch {
                    completion(nil, nil, error)
                }
            }
        }
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        return controller
    }

    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}
}
