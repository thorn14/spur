import SwiftUI

struct OptionDetailView: View {
    @EnvironmentObject var optionViewModel: OptionViewModel

    var body: some View {
        if let option = optionViewModel.selectedOption {
            OptionInfoView(option: option)
        } else {
            EmptyOptionView()
        }
    }
}

// MARK: - Option info (Phase 3)

private struct OptionInfoView: View {
    let option: SpurOption

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header bar
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(option.name)
                            .font(.title2).fontWeight(.semibold)
                        Text(option.branchName)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    PortBadge(port: option.port)
                    StatusBadge(status: option.status)
                }
                .padding()

                Divider()

                // Info rows
                VStack(alignment: .leading, spacing: 12) {
                    InfoRow(label: "Worktree", systemImage: "folder", value: option.worktreePath)

                    if let prURL = option.prURL, let url = URL(string: prURL) {
                        HStack(alignment: .top, spacing: 8) {
                            Label("Pull Request", systemImage: "arrow.triangle.pull")
                                .foregroundColor(.secondary)
                                .frame(width: 120, alignment: .leading)
                            Link(prURL, destination: url)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }

                    if let forked = option.forkedFromCommit {
                        InfoRow(label: "Forked from", systemImage: "arrow.branch", value: String(forked.prefix(12)))
                    }
                }
                .padding()

                Divider()

                // Phase 4 preview placeholder
                VStack(spacing: 12) {
                    Image(systemName: "play.circle")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary)
                    Text("Live preview available in Phase 4")
                        .foregroundColor(.secondary)
                    Text("Start the dev server to see the app running at http://localhost:\(option.port)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Empty state

private struct EmptyOptionView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.3.layers.3d")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No option selected")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Create or select an option from the tab bar above.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Sub-components

private struct InfoRow: View {
    let label: String
    let systemImage: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Label(label, systemImage: systemImage)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }
}

private struct PortBadge: View {
    let port: Int
    var body: some View {
        Text(":\(port)")
            .font(.system(.caption, design: .monospaced))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

private struct StatusBadge: View {
    let status: OptionStatus

    var body: some View {
        Text(status.rawValue.capitalized)
            .font(.caption).fontWeight(.medium)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private var color: Color {
        switch status {
        case .idle:     return .secondary
        case .running:  return .green
        case .detached: return .orange
        case .error:    return .red
        }
    }
}
