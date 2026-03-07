import SwiftUI

@main
struct SpurApp: App {
    @StateObject private var repoViewModel: RepoViewModel = makeRepoViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(repoViewModel)
                .task {
                    await repoViewModel.loadLastRepo()
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}

// MARK: - Factory

private func makeRepoViewModel() -> RepoViewModel {
    guard let persistence = try? PersistenceService() else {
        fatalError("[Spur] Cannot initialize PersistenceService — ~/.spur directory could not be created.")
    }
    return RepoViewModel(persistence: persistence)
}
