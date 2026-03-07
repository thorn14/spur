import SwiftUI
import AppKit

/// Initial screen shown when no repository is selected.
/// Uses NSOpenPanel for macOS-native directory selection.
struct RepoPickerView: View {
    @EnvironmentObject var repoViewModel: RepoViewModel
    @State private var validationError: String?

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            VStack(spacing: 8) {
                Text("Spur")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Explore multiple design ideas as parallel git branches,\neach with a live Next.js preview.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .font(.body)
            }

            VStack(spacing: 12) {
                Button("Open Repository…") {
                    openRepoPicker()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text("Select a local git repository containing package.json")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Group {
                if repoViewModel.isLoading {
                    ProgressView()
                } else if let errorMessage = validationError ?? repoViewModel.error?.localizedDescription {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(height: 32)
        }
        .padding(48)
        .frame(minWidth: 480, minHeight: 360)
    }

    // MARK: - Private

    private func openRepoPicker() {
        validationError = nil
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a git repository with package.json"
        panel.prompt = "Open"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let path = url.path
        let fm = FileManager.default

        guard fm.fileExists(atPath: (path as NSString).appendingPathComponent(".git")) else {
            validationError = "The selected directory is not a git repository (.git missing)."
            return
        }
        guard fm.fileExists(atPath: (path as NSString).appendingPathComponent("package.json")) else {
            validationError = "The selected directory does not contain a package.json."
            return
        }

        Task {
            await repoViewModel.selectRepo(path: path)
        }
    }
}
