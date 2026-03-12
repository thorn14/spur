import SwiftUI

/// Sheet for creating a GitHub pull request for the currently selected option.
struct CreatePRSheet: View {
    let option: SpurOption

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var optionViewModel: OptionViewModel

    @State private var title: String
    @State private var prBody: String = ""
    @State private var isCreating = false
    @State private var createdURL: String?
    @State private var error: Error?
    @FocusState private var titleFocused: Bool

    init(option: SpurOption) {
        self.option = option
        _title = State(initialValue: option.name)
    }

    private var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && !isCreating && createdURL == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // ── Header ────────────────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.pull")
                    .foregroundColor(.accentColor)
                Text("Create Pull Request")
                    .font(.headline)
            }

            if let url = createdURL {
                // ── Success state ──────────────────────────────────────
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Pull request created", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.subheadline.weight(.medium))

                        Link(url, destination: URL(string: url) ?? URL(string: "https://github.com")!)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(2)

                        Button("Copy URL") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(url, forType: .string)
                        }
                        .font(.caption)
                    }
                    .padding(4)
                }

                Spacer()

                HStack {
                    Spacer()
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }

            } else {
                // ── Form state ─────────────────────────────────────────
                VStack(alignment: .leading, spacing: 6) {
                    Text("Title")
                        .font(.subheadline)
                    TextField("Pull request title", text: $title)
                        .textFieldStyle(.roundedBorder)
                        .focused($titleFocused)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Description (optional)")
                        .font(.subheadline)
                    TextEditor(text: $prBody)
                        .font(.system(.body))
                        .frame(minHeight: 80)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                        )
                }

                VStack(alignment: .leading, spacing: 4) {
                    (Text("Branch: ").foregroundColor(.secondary)
                     + Text(option.branchName)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary))
                        .font(.caption)
                    Text("Tries gh CLI first, then opens browser compare page.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if let error {
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Spacer()

                HStack {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    if isCreating {
                        ProgressView()
                            .scaleEffect(0.7)
                            .padding(.trailing, 4)
                    }
                    Button("Create PR") { create() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(!canCreate)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 440, minHeight: 340)
        .onAppear { titleFocused = true }
    }

    private func create() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }
        isCreating = true
        error = nil

        Task {
            do {
                let url = try await optionViewModel.createPR(
                    for: option,
                    title: trimmedTitle,
                    body: prBody
                )
                createdURL = url
            } catch {
                self.error = error
            }
            isCreating = false
        }
    }
}
