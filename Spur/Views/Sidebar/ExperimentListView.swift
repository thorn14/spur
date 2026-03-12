import SwiftUI

struct PrototypeListView: View {
    @EnvironmentObject var prototypeViewModel: PrototypeViewModel
    @State private var showingNewPrototype = false

    var body: some View {
        List(
            prototypeViewModel.prototypes,
            id: \.id,
            selection: $prototypeViewModel.selectedPrototypeId
        ) { prototype in
            PrototypeRow(prototype: prototype)
                .tag(prototype.id)
        }
        .listStyle(.sidebar)
        .overlay {
            if prototypeViewModel.prototypes.isEmpty {
                EmptyPrototypesView { showingNewPrototype = true }
            }
        }
        .sheet(isPresented: $showingNewPrototype) {
            NewPrototypeSheet()
        }
    }
}

// MARK: - Row

private struct PrototypeRow: View {
    let prototype: Prototype

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(prototype.name, systemImage: "hammer")
                .lineLimit(1)
            Text("\(prototype.optionIds.count) option\(prototype.optionIds.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Empty state (macOS 13 compatible)

private struct EmptyPrototypesView: View {
    let onNew: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "hammer")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("No prototypes yet")
                .font(.callout)
                .foregroundColor(.secondary)
            Button("New Prototype", action: onNew)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
