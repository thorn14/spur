import SwiftUI

@main
struct SpurApp: App {
    @StateObject private var env = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(env.repoViewModel)
                .environmentObject(env.experimentViewModel)
                .environmentObject(env.optionViewModel)
                .task { await env.repoViewModel.loadLastRepo() }
                .onReceive(
                    NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
                ) { _ in
                    env.optionViewModel.stopAllServers()
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
