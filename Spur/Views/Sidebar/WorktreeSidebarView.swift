import SwiftUI

struct WorktreeSidebarView: View {
    @EnvironmentObject var optionViewModel: OptionViewModel
    @EnvironmentObject var prototypeViewModel: PrototypeViewModel
    @State private var searchText = ""
    @State private var newOptionPrototype: Prototype?
    @State private var showNewPrototype = false

    private var liveCount: Int {
        optionViewModel.allOptions.filter { $0.status == .running }.count
    }

    private var filteredOptions: [SpurOption] {
        let all = optionViewModel.allOptions
        guard !searchText.isEmpty else { return all }
        let q = searchText.lowercased()
        return all.filter {
            $0.name.lowercased().contains(q) ||
            $0.branchName.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Text("Worktrees")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(SpurColors.textPrimary)
                if liveCount > 0 {
                    Text("\(liveCount) live")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(SpurColors.accent)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(SpurColors.portBadgeBg)
                        .clipShape(Capsule())
                }
                Spacer()
                Menu {
                    if prototypeViewModel.prototypes.isEmpty {
                        Button("New Prototype first") { showNewPrototype = true }
                    } else {
                        ForEach(prototypeViewModel.prototypes) { exp in
                            Button(exp.name) { newOptionPrototype = exp }
                        }
                        Divider()
                        Button("New Prototype…") { showNewPrototype = true }
                    }
                } label: {
                    Image(systemName: "plus")
                        .foregroundColor(SpurColors.textSecondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(SpurColors.textMuted)
                TextField("Search worktrees…", text: $searchText)
                    .font(.system(size: 12))
                    .textFieldStyle(.plain)
                    .foregroundColor(SpurColors.textPrimary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(SpurColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(SpurColors.border, lineWidth: 1))
            .padding(.horizontal, 10)
            .padding(.bottom, 10)

            Divider().background(SpurColors.border)

            // Cards
            if filteredOptions.isEmpty {
                WorktreeEmptyState(
                    hasPrototypes: !prototypeViewModel.prototypes.isEmpty,
                    onNewPrototype: { showNewPrototype = true },
                    onNewOption: {
                        if let exp = prototypeViewModel.prototypes.first {
                            newOptionPrototype = exp
                        }
                    }
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredOptions) { option in
                            WorktreeCard(
                                option: option,
                                prototype: optionViewModel.prototype(for: option),
                                isSelected: option.id == optionViewModel.selectedOptionId
                            )
                            .onTapGesture {
                                optionViewModel.selectedOptionId = option.id
                                prototypeViewModel.selectedPrototypeId = option.prototypeId
                                optionViewModel.setPrototype(
                                    prototypeViewModel.prototypes.first { $0.id == option.prototypeId }
                                )
                            }
                        }
                    }
                    .padding(10)
                }
            }
        }
        .background(.ultraThinMaterial)
        .overlay(FilmGrainOverlay())
        .frame(width: 260)
        .sheet(item: $newOptionPrototype) { NewOptionSheet(prototype: $0) }
        .sheet(isPresented: $showNewPrototype) { NewPrototypeSheet() }
    }
}

// MARK: - Worktree Card

private struct WorktreeCard: View {
    let option: SpurOption
    let prototype: Prototype?
    let isSelected: Bool
    @EnvironmentObject var optionViewModel: OptionViewModel
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail area
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? SpurColors.selectedCard : SpurColors.surface)
                    .frame(height: 80)

                cardIcon
                    .font(.system(size: 28))
                    .foregroundColor(isSelected ? SpurColors.accent : SpurColors.textMuted)

                // Port badge
                VStack {
                    HStack {
                        Spacer()
                        Text(":\(option.port)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(SpurColors.accent)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(SpurColors.portBadgeBg)
                            .clipShape(Capsule())
                            .padding(6)
                    }
                    Spacer()
                }
                .frame(height: 80)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Info area
            VStack(alignment: .leading, spacing: 4) {
                // Status dot + name
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                    Text(option.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(SpurColors.textPrimary)
                        .lineLimit(1)
                }

                // Branch
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 9))
                        .foregroundColor(SpurColors.textMuted)
                    Text(option.branchName)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(SpurColors.textSecondary)
                        .lineLimit(1)
                }

                // Prototype tag
                if let exp = prototype {
                    HStack(spacing: 4) {
                        TagChip(exp.slug)
                        if option.status == .detached {
                            TagChip("detached", color: .orange)
                        }
                    }
                }
            }
            .padding(.top, 6)
            .padding(.horizontal, 2)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? SpurColors.selectedCard : (isHovered ? SpurColors.surfaceHover : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? SpurColors.accent.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Close", role: .destructive) {
                optionViewModel.removeOption(option.id)
            }
        }
    }

    private var cardIcon: Image {
        switch option.status {
        case .running:  return Image(systemName: "terminal.fill")
        case .detached: return Image(systemName: "exclamationmark.triangle")
        case .error:    return Image(systemName: "xmark.circle")
        case .idle:     return Image(systemName: "terminal")
        }
    }

    private var statusColor: Color {
        switch option.status {
        case .idle:     return SpurColors.textMuted
        case .running:  return SpurColors.statusRunning
        case .detached: return .orange
        case .error:    return .red
        }
    }
}

// MARK: - Tag chip

private struct TagChip: View {
    let text: String
    let color: Color
    init(_ text: String, color: Color = SpurColors.tagFg) {
        self.text = text
        self.color = color
    }
    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(SpurColors.tagBg)
            .clipShape(Capsule())
    }
}

// MARK: - Empty state

private struct WorktreeEmptyState: View {
    let hasPrototypes: Bool
    let onNewPrototype: () -> Void
    let onNewOption: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 32))
                .foregroundColor(SpurColors.textMuted)
            Text("No worktrees")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(SpurColors.textSecondary)
            if hasPrototypes {
                Button("New Option", action: onNewOption)
                    .buttonStyle(SpurButtonStyle())
            } else {
                Button("New Prototype", action: onNewPrototype)
                    .buttonStyle(SpurButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
