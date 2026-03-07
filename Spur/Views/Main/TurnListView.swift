import SwiftUI

/// Displays the turns for the currently selected option.
/// Shows start/end commits, allows capturing checkpoints, and forking from a checkpoint.
struct TurnListView: View {
    @EnvironmentObject var optionViewModel: OptionViewModel
    @EnvironmentObject var experimentViewModel: ExperimentViewModel

    /// Bound to the turn being forked (drives ForkFromCheckpointSheet).
    @State private var turnToFork: Turn?

    private var option: SpurOption? { optionViewModel.selectedOption }
    private var turns: [Turn] {
        guard let id = option?.id else { return [] }
        return optionViewModel.turns(for: id)
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──────────────────────────────────────────────────
            HStack {
                Text("Turns")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                Button {
                    Task { await optionViewModel.startTurn() }
                } label: {
                    Label("New Turn", systemImage: "plus.circle")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .disabled(option == nil || optionViewModel.isLoading)
                .help("Start a new turn (records current HEAD)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // ── Turn list ────────────────────────────────────────────────
            if turns.isEmpty {
                EmptyTurnsView()
            } else {
                List {
                    ForEach(turns) { turn in
                        TurnRow(turn: turn, turnToFork: $turnToFork)
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
        .sheet(item: $turnToFork) { turn in
            if let experiment = experimentViewModel.selectedExperiment {
                ForkFromCheckpointSheet(turn: turn, experiment: experiment)
            }
        }
    }
}

// MARK: - Turn row

private struct TurnRow: View {
    let turn: Turn
    @Binding var turnToFork: Turn?
    @EnvironmentObject var optionViewModel: OptionViewModel

    private var isCapturing: Bool { optionViewModel.isLoading }
    private var shortStart: String { String(turn.startCommit.prefix(7)) }
    private var shortEnd: String? { turn.endCommit.map { String($0.prefix(7)) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // ── Title row ──────────────────────────────────────────────
            HStack {
                Label(turn.label, systemImage: "arrow.right.circle")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(turn.createdAt, style: .date)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // ── Commit range ───────────────────────────────────────────
            HStack(spacing: 4) {
                CommitTag(hash: shortStart, label: "start")
                if let end = shortEnd {
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    CommitTag(hash: end, label: "end")
                    Text("(\(turn.commitRange.count) commit\(turn.commitRange.count == 1 ? "" : "s"))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // ── Actions ────────────────────────────────────────────────
            HStack(spacing: 8) {
                if turn.endCommit == nil {
                    Button {
                        Task { await optionViewModel.captureCheckpoint(turn: turn) }
                    } label: {
                        Label("Capture", systemImage: "camera")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isCapturing)
                    .help("Commit uncommitted changes and record this checkpoint")
                } else {
                    Button {
                        turnToFork = turn
                    } label: {
                        Label("Fork", systemImage: "tuningfork")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .help("Create a new option branched from this checkpoint")
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

private struct EmptyTurnsView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.right.circle")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text("No turns yet")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Click \"New Turn\" to record the current state.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
