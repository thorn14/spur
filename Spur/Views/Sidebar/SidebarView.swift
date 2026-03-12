import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var repoViewModel: RepoViewModel
    @EnvironmentObject var prototypeViewModel: PrototypeViewModel
    @State private var showingNewPrototype = false

    var body: some View {
        VStack(spacing: 0) {
            // Repo identity header
            if let repo = repoViewModel.currentRepo {
                RepoHeaderView(repoPath: repo.path)
                Divider()
            }

            // Prototype list
            PrototypeListView()

            Divider()

            // "New Prototype" footer button
            Button {
                showingNewPrototype = true
            } label: {
                Label("New Prototype", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .sheet(isPresented: $showingNewPrototype) {
            NewPrototypeSheet()
        }
        .frame(minWidth: 200)
    }
}

// MARK: - Repo header

private struct RepoHeaderView: View {
    let repoPath: String

    private var repoName: String {
        URL(fileURLWithPath: repoPath).lastPathComponent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(repoName, systemImage: "folder.badge.gearshape")
                .font(.headline)
                .lineLimit(1)
            Text(repoPath)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
