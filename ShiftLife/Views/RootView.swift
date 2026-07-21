import SwiftUI

/// Bottom tab navigation for the five core views + a central Quick-Add button.
struct RootView: View {
    @EnvironmentObject var store: AppStore
    @State private var showQuickAdd = false

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Heute", systemImage: "sun.max.fill") }

            WeekView()
                .tabItem { Label("Woche", systemImage: "calendar") }

            CommonTimeView()
                .tabItem { Label("Gemeinsam", systemImage: "person.2.fill") }

            ConflictsView()
                .tabItem { Label("Konflikte", systemImage: "exclamationmark.triangle.fill") }

            TasksView()
                .tabItem { Label("Aufgaben", systemImage: "checklist") }
        }
        .overlay(alignment: .bottom) {
            // Central quick-add button floating above the tab bar.
            Button {
                showQuickAdd = true
            } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Theme.brand, in: Circle())
                    .shadow(color: Theme.brand.opacity(0.4), radius: 8, y: 4)
            }
            .accessibilityLabel("Schnell hinzufügen")
            .offset(y: -28)
        }
        .sheet(isPresented: $showQuickAdd) {
            QuickAddView()
        }
    }
}
