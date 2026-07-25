import SwiftUI

struct RootTabView: View {
    @Binding var openNewSession: Bool

    var body: some View {
        TabView {
            SessionsListView(openNewSession: $openNewSession)
                .tabItem { Label("Sessions", systemImage: "calendar") }

            RosterView()
                .tabItem { Label("Roster", systemImage: "person.3") }

            InsightsView()
                .tabItem { Label("Insights", systemImage: "chart.bar") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
