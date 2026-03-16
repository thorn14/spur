import SwiftUI

/// Shown after opening a new repository (or when setup is incomplete).
/// Asks for install and dev server commands, with suggestions auto-detected
/// from lockfiles in the repo.
struct RepoSetupSheet: View {
    @EnvironmentObject var repoViewModel: RepoViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var installCommand: String
    @State private var devCommand: String

    private let repoPath: String
    private let detected: RepoDetection

    init(repoPath: String) {
        self.repoPath = repoPath
        let d = RepoDetection(repoPath: repoPath)
        self.detected = d
        _installCommand = State(initialValue: d.installCommand)
        _devCommand     = State(initialValue: d.devCommand)
    }

    private var canSave: Bool {
        !installCommand.trimmingCharacters(in: .whitespaces).isEmpty &&
        !devCommand.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "gearshape")
                    .font(.title2)
                    .foregroundColor(SpurColors.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Configure Repository")
                        .font(.headline)
                        .foregroundColor(SpurColors.textPrimary)
                    Text(URL(fileURLWithPath: repoPath).lastPathComponent)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(SpurColors.textSecondary)
                }
            }

            Text("These commands will run automatically for every new worktree. You can change them later in repo settings.")
                .font(.caption)
                .foregroundColor(SpurColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // Install command
            commandField(
                label: "Install command",
                hint: "Run once after creating each new worktree",
                icon: "arrow.down.circle",
                text: $installCommand,
                suggestions: detected.installSuggestions
            )

            // Dev command
            commandField(
                label: "Dev server command",
                hint: "Start the development server",
                icon: "play.circle",
                text: $devCommand,
                suggestions: detected.devSuggestions
            )

            Spacer()

            HStack {
                Button("Skip for now") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundColor(SpurColors.textMuted)
                Spacer()
                Button("Save") {
                    repoViewModel.updateSetup(
                        installCommand: installCommand.trimmingCharacters(in: .whitespaces),
                        devCommand: devCommand.trimmingCharacters(in: .whitespaces)
                    )
                    dismiss()
                }
                .buttonStyle(SpurButtonStyle())
                .disabled(!canSave)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(minWidth: 460, minHeight: 380)
        .background(SpurColors.background)
    }

    // MARK: - Command field

    @ViewBuilder
    private func commandField(
        label: String,
        hint: String,
        icon: String,
        text: Binding<String>,
        suggestions: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(SpurColors.accent)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(SpurColors.textPrimary)
            }
            TextField(hint, text: text)
                .font(.system(size: 12, design: .monospaced))
                .textFieldStyle(.plain)
                .foregroundColor(SpurColors.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(SpurColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(SpurColors.border, lineWidth: 1))

            // Quick-pick suggestions
            HStack(spacing: 6) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button(suggestion) { text.wrappedValue = suggestion }
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(text.wrappedValue == suggestion ? SpurColors.accent : SpurColors.textMuted)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(
                            text.wrappedValue == suggestion
                                ? SpurColors.portBadgeBg
                                : SpurColors.tagBg
                        )
                        .clipShape(Capsule())
                        .buttonStyle(.plain)
                }
            }
        }
    }

}

// MARK: - Repo detection

/// Reads lockfiles and package.json from the repo to produce context-aware
/// install/dev command suggestions. Nothing is hardcoded — if a file isn't
/// present, the corresponding suggestion list is empty.
struct RepoDetection {
    let packageManager: String?   // "pnpm" | "yarn" | "npm" | nil
    let installCommand: String    // pre-filled default, or ""
    let devCommand: String        // pre-filled default, or ""
    let installSuggestions: [String]
    let devSuggestions: [String]

    init(repoPath: String) {
        let fm = FileManager.default
        func has(_ f: String) -> Bool {
            fm.fileExists(atPath: (repoPath as NSString).appendingPathComponent(f))
        }

        // Detect package manager from lockfiles only.
        let pm: String?
        if has("pnpm-lock.yaml")            { pm = "pnpm" }
        else if has("yarn.lock")            { pm = "yarn" }
        else if has("package-lock.json")    { pm = "npm" }
        else                                { pm = nil }

        self.packageManager = pm

        // Install suggestion comes solely from the detected PM.
        let installCmd: String
        switch pm {
        case "pnpm": installCmd = "pnpm install"
        case "yarn": installCmd = "yarn"
        case "npm":  installCmd = "npm install"
        default:     installCmd = ""
        }
        self.installCommand = installCmd
        self.installSuggestions = installCmd.isEmpty ? [] : [installCmd]

        // Read scripts from package.json.
        let pkgPath = (repoPath as NSString).appendingPathComponent("package.json")
        var scriptNames: [String] = []
        if let data = fm.contents(atPath: pkgPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let scripts = json["scripts"] as? [String: Any] {
            // Surface common dev-related script names in a stable order.
            let preferred = ["dev", "start", "serve", "develop", "watch"]
            let found = preferred.filter { scripts[$0] != nil }
            scriptNames = found
        }

        // Build dev suggestions from the actual scripts × the detected PM.
        var devCmds: [String] = []
        if let pm {
            for script in scriptNames {
                // pnpm/yarn support shorthand `pnpm dev`; npm needs `npm run dev`
                let cmd = (pm == "npm") ? "npm run \(script)" : "\(pm) \(script)"
                devCmds.append(cmd)
            }
        }
        self.devSuggestions = devCmds
        self.devCommand = devCmds.first ?? ""
    }
}
