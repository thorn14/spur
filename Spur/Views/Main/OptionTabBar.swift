import SwiftUI

struct OptionTabBar: View {
    @EnvironmentObject var experimentViewModel: ExperimentViewModel
    @EnvironmentObject var optionViewModel: OptionViewModel
    @State private var newOptionExperiment: Experiment?

    var body: some View {
        HStack(spacing: 0) {
            // Scrollable tab strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    if optionViewModel.options.isEmpty {
                        Text("No options — click + to create one")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                    } else {
                        ForEach(optionViewModel.options) { option in
                            OptionTab(
                                option: option,
                                isSelected: option.id == optionViewModel.selectedOptionId
                            )
                            .onTapGesture { optionViewModel.selectedOptionId = option.id }
                        }
                    }
                }
                .frame(minHeight: 36)
            }

            Divider().frame(height: 20)

            // Add-option button
            Button {
                newOptionExperiment = experimentViewModel.selectedExperiment
            } label: {
                Image(systemName: "plus")
                    .padding(.horizontal, 10)
                    .frame(height: 36)
            }
            .buttonStyle(.plain)
            .help("New Option (⌘T)")
            .disabled(experimentViewModel.selectedExperiment == nil)
            .keyboardShortcut("t", modifiers: .command)
        }
        .frame(height: 36)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(item: $newOptionExperiment) { experiment in
            NewOptionSheet(experiment: experiment)
        }
    }
}

// MARK: - Individual tab button

private struct OptionTab: View {
    let option: SpurOption
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(option.name)
                .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .overlay(alignment: .bottom) {
            if isSelected {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
            }
        }
        .contentShape(Rectangle())
        .help("Port \(option.port) · \(option.branchName)")
    }

    private var statusColor: Color {
        switch option.status {
        case .idle:     return .secondary
        case .running:  return .green
        case .detached: return .orange
        case .error:    return .red
        }
    }
}
