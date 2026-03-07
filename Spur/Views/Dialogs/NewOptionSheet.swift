import SwiftUI

struct NewOptionSheet: View {
    /// The experiment this option will belong to.
    let experiment: Experiment

    @EnvironmentObject var optionViewModel: OptionViewModel
    @EnvironmentObject var repoViewModel: RepoViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var fromMain = true     // false = from checkpoint (Phase 5)
    @FocusState private var nameFieldFocused: Bool

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }
    private var isValid: Bool { !trimmed.isEmpty }
    private var baseBranch: String { repoViewModel.currentRepo?.baseBranch ?? "main" }
    private var previewBranch: String {
        let slug = SlugGenerator.generate(from: trimmed.isEmpty ? "…" : trimmed)
        return "exp/\(experiment.slug)/\(slug)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("New Option")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)

            // Experiment context
            Label(experiment.name, systemImage: "flask")
                .font(.caption)
                .foregroundColor(.secondary)

            // Name input
            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("e.g. Warm Palette", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFieldFocused)
                    .onSubmit { Task { await createIfValid() } }
                if !trimmed.isEmpty {
                    Text("Branch: \(previewBranch)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            // Source picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Starting point")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("Source", selection: $fromMain) {
                    Text("From \(baseBranch)").tag(true)
                    Text("From checkpoint  (Phase 5)").tag(false)
                }
                .pickerStyle(.radioGroup)
                if !fromMain {
                    Text("Checkpoint-based forking is available in Phase 5.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // Loading / error feedback
            Group {
                if optionViewModel.isLoading {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text("Creating branch and worktree…")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if let error = optionViewModel.error {
                    Text(error.localizedDescription)
                        .foregroundColor(.red)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(minHeight: 24)

            HStack {
                Button("Cancel") {
                    optionViewModel.error = nil
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Button("Create") { Task { await createIfValid() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid || optionViewModel.isLoading || !fromMain)
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(24)
        .frame(minWidth: 400, minHeight: 280)
        .onAppear {
            nameFieldFocused = true
            optionViewModel.error = nil
        }
    }

    private func createIfValid() async {
        guard isValid, fromMain else { return }
        await optionViewModel.createOption(
            name: name,
            experiment: experiment,
            source: .main(baseBranch)
        )
        if optionViewModel.error == nil {
            dismiss()
        }
    }
}
