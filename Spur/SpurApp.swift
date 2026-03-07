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
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
