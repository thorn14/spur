import SwiftUI

struct OptionTabBar: View {
    @EnvironmentObject var prototypeViewModel: PrototypeViewModel
    @EnvironmentObject var optionViewModel: OptionViewModel
    @State private var newOptionPrototype: Prototype?

    var body: some View {
        HStack(spacing: 0) {
            // Scrollable tab strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    if optionViewModel.options.isEmpty {
                        if let prototype = prototypeViewModel.selectedPrototype {
                            Button("New Option") {
                                newOptionPrototype = prototype
                            }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 12)
                        } else {
                            Text("Select an prototype to add options")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                        }
                    } else {
                        ForEach(optionViewModel.options) { option in
                            OptionTab(
                                option: option,
                                isSelected: option.id == optionViewModel.selectedOptionId,
                                onClose: { optionViewModel.removeOption(option.id) }
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
                newOptionPrototype = prototypeViewModel.selectedPrototype
            } label: {
                Image(systemName: "plus")
                    .padding(.horizontal, 10)
                    .frame(height: 36)
            }
            .buttonStyle(.plain)
            .help("New Option (⌘T)")
            .disabled(prototypeViewModel.selectedPrototype == nil)
            .keyboardShortcut("t", modifiers: .command)
        }
        .frame(height: 36)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(item: $newOptionPrototype) { prototype in
            NewOptionSheet(prototype: prototype)
        }
    }
}

// MARK: - Individual tab button

private struct OptionTab: View {
    let option: SpurOption
    let isSelected: Bool
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(option.name)
                .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                .lineLimit(1)
            // Close button — visible on hover or when selected
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isHovered || isSelected ? 1 : 0)
            .help("Close option")
        }
        .padding(.horizontal, 10)
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
        .onHover { isHovered = $0 }
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
