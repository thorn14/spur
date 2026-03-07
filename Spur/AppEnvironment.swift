import Foundation
import os

private let logger = Logger(subsystem: Constants.appSubsystem, category: "AppEnvironment")

/// Owns all app-wide services and view models.
///
/// Created once in `SpurApp` and injected into the SwiftUI environment so every
/// view shares a single instance of each service and view model.
@MainActor
final class AppEnvironment: ObservableObject {
    let repoViewModel: RepoViewModel
    let experimentViewModel: ExperimentViewModel
    let optionViewModel: OptionViewModel
    let devServerService: DevServerService

    init() {
        guard let persistence = try? PersistenceService() else {
            fatalError("[Spur] Cannot create PersistenceService — ~/.spur directory unavailable.")
        }
        let git       = GitService()
        let devServer = DevServerService()
        let rvm       = RepoViewModel(persistence: persistence)
        self.repoViewModel       = rvm
        self.experimentViewModel = ExperimentViewModel(repoViewModel: rvm)
        self.optionViewModel     = OptionViewModel(repoViewModel: rvm, git: git, devServer: devServer)
        self.devServerService    = devServer
        logger.debug("AppEnvironment initialized")
    }
}
