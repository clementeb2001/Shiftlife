import SwiftUI

@main
struct ShiftLifeApp: App {
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if store.data.hasCompletedOnboarding {
                    RootView()
                } else {
                    OnboardingView()
                }
            }
            .environmentObject(store)
            .tint(Theme.brand)
            .onAppear {
                // Start iCloud family sync only if the user turned it on (off by
                // default → app stays fully local). See CloudSync / CLOUDKIT.md.
                CloudSync.shared.startIfEnabled(store)
                startDetectionIfEnabled()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    NotificationManager.reschedule(store.data)   // keep reminders current
                    CloudSync.shared.refresh()                    // pull latest from iCloud
                    startDetectionIfEnabled()                     // re-arm geofences
                }
            }
        }
    }

    /// Registers geofences for Smart Shift Detection when the user enabled it.
    private func startDetectionIfEnabled() {
        guard store.data.autoDetectEnabled, !store.data.workplaces.isEmpty else { return }
        LocationMonitor.shared.startMonitoring(store.data.workplaces)
    }
}
