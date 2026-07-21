import SwiftUI

@main
struct ShiftLifeApp: App {
    @StateObject private var store = AppStore()

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
        }
    }
}
