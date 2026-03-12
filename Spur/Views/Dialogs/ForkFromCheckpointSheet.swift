import SwiftUI

/// Sheet for creating a new Option branched from a captured checkpoint (turn.endCommit).
struct ForkFromCheckpointSheet: View {
    let turn: Turn
    let prototype: Prototype

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var optionViewModel: OptionViewModel

    @State private var name = ""
    @FocusState private var nameFocused: Bool

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !optionViewModel.isLoading
    }

    private var shortCommit: String { String((turn.endCommit ?? "").prefix(7)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // ── Title ──────────────────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "tuningfork")
                    .foregroundColor(.accentColor)
                Text("Fork from Checkpoint")
                    .font(.headline)
            }

            // ── Source info ────────────────────────────────────────────
            GroupBox {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(turn.label)
                            .font(.subheadline).fontWeight(.medium)
                        Text("Commit: \(shortCommit)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text("\(turn.commitRange.count) commit\(turn.commitRange.count == 1 ? "" : "s") in this checkpoint")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(4)
            } label: {
                Text("Source checkpoint")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // ── Name input ─────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 6) {
                Text("New option name")
                    .font(.subheadline)
                TextField("e.g. warm-palette-v2", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFocused)
                    .onSubmit { if canSubmit { fork() } }
                Text("Branch: \(prototype.slug)/\(SlugGenerator.generate(from: name.isEmpty ? "…" : name))")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            // ── Error ──────────────────────────────────────────────────
            if let error = optionViewModel.error {
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Spacer()

            // ── Actions ────────────────────────────────────────────────
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Fork") { fork() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 360, minHeight: 320)
        .onAppear { nameFocused = true }
    }

    private func fork() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, turn.endCommit != nil else { return }
        Task {
            await optionViewModel.forkFromCheckpoint(turn: turn, name: trimmed, prototype: prototype)
            if optionViewModel.error == nil { dismiss() }
        }
    }
}
