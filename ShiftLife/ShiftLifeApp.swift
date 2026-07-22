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
            .onChange(of: scenePhase) { _, phase in
                // Keep local reminders in sync with the current plan.
                if phase == .active { NotificationManager.reschedule(store.data) }
            }
        }
    }
}
