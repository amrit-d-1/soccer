import SwiftUI

@main
struct SoccerLogApp: App {
    @StateObject private var store = DataStore()
    @StateObject private var connectivity = Connectivity.shared
    @Environment(\.scenePhase) private var scenePhase

    /// Set when a "Log tonight's game" notification is tapped, so the root can
    /// open straight into the New Session sheet.
    @State private var openNewSession = false

    var body: some Scene {
        WindowGroup {
            Group {
                if store.isAuthenticated {
                    RootTabView(openNewSession: $openNewSession)
                } else {
                    AuthView()
                }
            }
            .environmentObject(store)
            .environmentObject(connectivity)
            .tint(Theme.amber)
            .task {
                await store.bootstrap()
                await store.flushQueue()
                NotificationManager.shared.registerCategories()
            }
            .onReceive(NotificationManager.shared.openNewSession) { _ in
                openNewSession = true
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await store.flushQueue() }
            }
        }
    }
}
