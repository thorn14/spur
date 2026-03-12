import Combine
import Foundation
import os

private let logger = Logger(subsystem: Constants.appSubsystem, category: "PrototypeViewModel")

@MainActor
final class PrototypeViewModel: ObservableObject {
    // MARK: - Published state

    /// ID of the currently selected prototype.
    @Published var selectedPrototypeId: UUID?
    /// Non-nil when an operation fails.
    @Published var error: Error?

    // MARK: - Derived accessors (computed from AppState — no duplication)

    var prototypes: [Prototype] {
        repoViewModel.appState?.prototypes ?? []
    }

    var selectedPrototype: Prototype? {
        guard let id = selectedPrototypeId else { return nil }
        return prototypes.first { $0.id == id }
    }

    // MARK: - Dependencies

    private let repoViewModel: RepoViewModel
    private var cancellables = Set<AnyCancellable>()

    init(repoViewModel: RepoViewModel) {
        self.repoViewModel = repoViewModel
        // Forward AppState mutations so observing views re-render when prototypes list changes.
        repoViewModel.$appState
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    /// Creates an prototype, persists it, and selects it immediately.
    func createPrototype(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        error = nil

        let slug = SlugGenerator.generate(from: trimmed)
        let prototype = Prototype(name: trimmed, slug: slug)
        repoViewModel.appState?.prototypes.append(prototype)
        repoViewModel.persistState()
        selectedPrototypeId = prototype.id
        logger.info("Created prototype '\(trimmed)' slug='\(slug)'")
    }
}
