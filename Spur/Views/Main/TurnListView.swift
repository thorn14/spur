import SwiftUI

/// Displays the checkpoints for the currently selected option.
/// Checkpoints are captured automatically when Enter is pressed in the terminal.
/// Manual capture, new-turn, roll-back, and "New Exploration" (fork) are also available.
struct TurnListView: View {
    @EnvironmentObject var optionViewModel: OptionViewModel
    @EnvironmentObject var prototypeViewModel: PrototypeViewModel

    @State private var turnToFork: Turn?
    @State private var turnToRollback: Turn?

    private var option: SpurOption? { optionViewModel.selectedOption }
    private var turns: [Turn] {
        guard let id = option?.id else { return [] }
        return optionViewModel.turns(for: id)
    }
    /// Latest captured turn available for forking.
    private var latestCaptured: Turn? {
        guard let id = option?.id else { return nil }
        return optionViewModel.latestCapturedTurn(for: id)
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──────────────────────────────────────────────────
            HStack(spacing: 6) {
                Text("Checkpoints")
                    .font(.headline)
                    .foregroundColor(SpurColors.textPrimary)
                Spacer()
                // Manual new-turn (secondary icon button)
                Button {
                    Task { await optionViewModel.startTurn() }
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 13))
                        .foregroundColor(SpurColors.textSecondary)
                }
                .buttonStyle(.plain)
                .disabled(option == nil || optionViewModel.isLoading)
                .help("Manually start a new turn")

                // Primary CTA — "New Exploration"
                Button {
                    if let turn = latestCaptured {
                        turnToFork = turn
                    }
                } label: {
                    Label("New Exploration", systemImage: "tuningfork")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(GreenButtonStyle())
                .disabled(latestCaptured == nil || optionViewModel.isLoading)
                .help("Fork a new option from the latest checkpoint")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(SpurColors.surface)

            Divider()

            // ── Turn list ────────────────────────────────────────────────
            if turns.isEmpty {
                EmptyCheckpointsView(onNewTurn: { Task { await optionViewModel.startTurn() } })
            } else {
                List {
                    ForEach(turns) { turn in
                        TurnRow(turn: turn, turnToFork: $turnToFork, turnToRollback: $turnToRollback)
                    }
                }
                .listStyle(.inset)
            }

            // ── Error banner ────────────────────────────────────────────
            if let error = optionViewModel.error {
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.07))
            }
        }
        // Fork sheet
        .sheet(item: $turnToFork) { turn in
            if let prototype = prototypeViewModel.selectedPrototype {
                ForkFromCheckpointSheet(turn: turn, prototype: prototype)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundColor(SpurColors.textMuted)
                    Text("No Prototype Selected")
                        .font(.headline)
                        .foregroundColor(SpurColors.textPrimary)
                    Text("Select a prototype in the sidebar before forking a checkpoint.")
                        .font(.caption)
                        .foregroundColor(SpurColors.textMuted)
                        .multilineTextAlignment(.center)
                    Button("Dismiss") { turnToFork = nil }
                        .buttonStyle(.bordered)
                }
                .padding(24)
                .frame(width: 320)
            }
        }
        // Roll-back confirmation
        .alert("Roll Back to Checkpoint?", isPresented: .init(
            get: { turnToRollback != nil },
            set: { if !$0 { turnToRollback = nil } }
        )) {
            Button("Roll Back", role: .destructive) {
                guard let turn = turnToRollback else { return }
                turnToRollback = nil
                Task { await optionViewModel.rollbackToCheckpoint(turn: turn) }
            }
            Button("Cancel", role: .cancel) { turnToRollback = nil }
        } message: {
            if let turn = turnToRollback {
                Text("This will hard-reset the worktree to commit \(String(turn.endCommit?.prefix(7) ?? ""))."
                   + " All later commits and uncommitted changes will be lost.")
            }
        }
    }
}

// MARK: - Turn row

private struct TurnRow: View {
    let turn: Turn
    @Binding var turnToFork: Turn?
    @Binding var turnToRollback: Turn?
    @EnvironmentObject var optionViewModel: OptionViewModel

    private var shortStart: String { String(turn.startCommit.prefix(7)) }
    private var shortEnd: String? { turn.endCommit.map { String($0.prefix(7)) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // ── Title row ──────────────────────────────────────────────
            HStack {
                Label(turn.label, systemImage: turn.endCommit == nil ? "clock" : "checkmark.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(turn.endCommit == nil ? SpurColors.accent : SpurColors.textPrimary)
                Spacer()
                if turn.isAutomatic {
                    Text("auto")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(SpurColors.textMuted)
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                Text(turn.createdAt, style: .date)
                    .font(.caption2)
                    .foregroundColor(SpurColors.textSecondary)
            }

            // ── Commit range ───────────────────────────────────────────
            HStack(spacing: 4) {
                CommitTag(hash: shortStart, label: "start")
                if let end = shortEnd {
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundColor(SpurColors.textSecondary)
                    CommitTag(hash: end, label: "end")
                    Text("(\(turn.commitRange.count) commit\(turn.commitRange.count == 1 ? "" : "s"))")
                        .font(.caption2)
                        .foregroundColor(SpurColors.textSecondary)
                } else {
                    Text("recording…")
                        .font(.caption2)
                        .foregroundColor(SpurColors.accent)
                        .italic()
                }
            }

            // ── Actions ────────────────────────────────────────────────
            HStack(spacing: 6) {
                if turn.endCommit == nil {
                    // Open turn: manual capture override
                    Button {
                        Task { await optionViewModel.captureCheckpoint(turn: turn) }
                    } label: {
                        Label("Capture Now", systemImage: "camera")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .disabled(optionViewModel.isLoading)
                    .help("Manually capture this checkpoint now")
                } else {
                    // Captured turn: explore or roll back
                    Button {
                        turnToFork = turn
                    } label: {
                        Label("Explore", systemImage: "tuningfork")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .help("Fork a new option branched from this checkpoint")

                    Button {
                        turnToRollback = turn
                    } label: {
                        Label("Roll Back", systemImage: "arrow.uturn.backward")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color(hex: "F87171"))
                    .help("Reset the worktree to this checkpoint (destructive)")
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Supporting views

private struct CommitTag: View {
    let hash: String
    let label: String

    var body: some View {
        Text(hash)
            .font(.system(.caption2, design: .monospaced))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .help("\(label) commit: \(hash)")
    }
}

private struct EmptyCheckpointsView: View {
    var onNewTurn: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.arrow.2.circlepath")
                .font(.system(size: 28))
                .foregroundColor(SpurColors.textMuted)
            Text("No checkpoints yet")
                .font(.subheadline)
                .foregroundColor(SpurColors.textSecondary)
            Text("Checkpoints are captured automatically\nwhen you press Enter in the terminal.")
                .font(.caption)
                .foregroundColor(SpurColors.textMuted)
                .multilineTextAlignment(.center)
            if let onNewTurn {
                Button("New Turn", action: onNewTurn)
                    .buttonStyle(SpurButtonStyle())
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
