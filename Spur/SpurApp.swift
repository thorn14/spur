import SwiftUI

@main
struct SpurApp: App {
    @StateObject private var env = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(env.repoViewModel)
                .environmentObject(env.prototypeViewModel)
                .environmentObject(env.optionViewModel)
                .task {
                    await env.repoViewModel.loadLastRepo()
                    await env.optionViewModel.reconcileWorktrees()
                }
                .onReceive(
                    NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
                ) { _ in
                    env.optionViewModel.stopAllServers()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 700)
    }
}
