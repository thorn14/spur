# Spur — Engineering Plan

> **Spur** is a native macOS app that helps designers and engineers explore multiple web prototype ideas quickly by creating git branches + git worktrees per idea, running a Next.js dev server per worktree, and embedding the preview in-app.

## 1. Product Vision

Spur is built for **rapid exploration of design concepts** — a canvas-style workflow adapted for web product prototyping. The core loop is:

1. **Start an Experiment** (a design exploration session).
2. **Create Options** (divergent ideas), each backed by a git branch + worktree.
3. **Run external agentic coding tools** (Claude Code, Codex CLI, Aider, etc.) in each Option's worktree via a command panel.
4. **Capture Checkpoints** (Turns) that link units of work to git commits.
5. **Fork from any Checkpoint** to explore a different direction from that exact code state.
6. **Compare Options** side-by-side in tabs — live previews of running dev servers.
7. **Create a PR** from any Option to ship the winning idea.

The "chat" surface is **not** a traditional in-app LLM chat. Instead, Spur provides a terminal/command panel to run any external tool. Turns/Checkpoints are first-class units, linking each Turn to one or more git commits so that "fork from Turn N" is deterministic and comparable.

**Rule A:** Every Option branch is pushed to `origin` on creation, and pushed again after each checkpoint commit.

---

## 2. Branch + Worktree Philosophy

This philosophy is **central** to Spur and must be understood by every contributor.

### 2.1 Core Concepts

| Concept | What it is |
|---------|-----------|
| **Branch** | The durable identity. It is what gets pushed, what PRs are opened from, and what persists after the worktree is removed. |
| **Worktree** | A lightweight additional working directory — a checkout of a branch in a separate folder. It allows multiple branches to be checked out simultaneously in the same repo. |
| **Option** | The app-level object that owns a branch + worktree + dev server + terminal session + list of Turns. |

### 2.2 Two Creation Modes

#### A) "Branch from main" (default — new exploration)

Start a new Option from the base branch (default: `main`). This is the typical starting point for a fresh idea.

```bash
# 1. Create branch from main
git branch exp/color-study/warm-palette main

# 2. Create worktree in the worktrees directory
git worktree add ../spur-worktrees/color-study--warm-palette exp/color-study/warm-palette

# 3. Push immediately (Rule A)
git push -u origin exp/color-study/warm-palette
```

#### B) "Branch+worktree from commit" (forking from a Turn/Checkpoint)

Each Checkpoint records a commit hash representing the exact repo state after a unit of work. Forking creates a new branch+worktree **rooted at that commit hash** — not at `main` — yielding deterministic divergence.

```bash
# Suppose checkpoint commit is abc1234
# 1. Create branch starting at that exact commit
git branch exp/color-study/warm-v2 abc1234

# 2. Create worktree from that branch (which points at abc1234)
git worktree add ../spur-worktrees/color-study--warm-v2 exp/color-study/warm-v2

# 3. Push immediately (Rule A)
git push -u origin exp/color-study/warm-v2
```

The resulting worktree has the filesystem state of `abc1234`. Any new work diverges from that point. This is how you get **deterministic, comparable forks**.

#### C) Why worktree + branch (not just branch)?

- **Worktree** = you can have multiple Options checked out simultaneously, run separate dev servers, and switch between them without `git checkout`.
- **Branch** = durable. It is what you push, open PRs from, and reference later. Worktrees can be added/removed freely; branches persist.

### 2.3 Branch Naming Convention

```
exp/<experimentId>/<optionSlug>
```

- `experimentId`: kebab-case, derived from Experiment name (e.g., `color-study`).
- `optionSlug`: kebab-case, derived from Option name (e.g., `warm-palette`).
- Slugs are sanitized: lowercase, alphanumeric + hyphens only, max 50 chars.

### 2.4 Worktree Directory Convention

Worktrees are stored **outside** the main repo directory to avoid nesting:

```
<repoParent>/spur-worktrees/<experimentId>--<optionSlug>/
```

Example: if the repo is at `/Users/me/projects/my-app`, worktrees go in `/Users/me/projects/spur-worktrees/color-study--warm-palette/`.

---

## 3. Requirements

### 3.1 Functional Requirements

| ID | Requirement | Details |
|----|------------|---------|
| F1 | **Repo selection** | User selects an existing local git repo (expected to be a Next.js app). Validate that `.git` exists and a `package.json` is present. |
| F2 | **Experiments** | Grouping container for Options. Has a name, ID, creation date, and a list of Option IDs. |
| F3 | **Options (tabs)** | Each Option = branch + worktree + dev server port + terminal session + list of Turns. Displayed as tabs for fast switching/comparison. |
| F4 | **Branch+worktree creation** | Two modes: "from main" (default) and "from checkpoint commit". See §2. |
| F5 | **Worktree lifecycle** | Create, remove locally (stop server, `git worktree remove`), refresh/reconcile with persisted state. No destructive remote deletion in MVP. |
| F6 | **Dev server** | Start/stop `npm run dev` (or configurable command) per Option. Allocate unique port. Stream stdout/stderr logs. |
| F7 | **Live preview** | WKWebView loads `http://localhost:<port>` for the selected Option. Multiple Options may run concurrently. |
| F8 | **Command Runner (Phase 1)** | Panel that runs arbitrary commands in the Option's worktree directory with streaming output. Plus "Open in Terminal.app" shortcut. |
| F9 | **PTY terminal (Phase 2)** | Optional embedded PTY-backed terminal emulator. Planned, not required for initial milestone. |
| F10 | **Turns/Checkpoints** | User creates a Turn, then "Capture Checkpoint" to link work to git. Handles tools that commit (record commit range) and tools that don't (app commits). After checkpoint, push branch (Rule A). |
| F11 | **Fork from checkpoint** | Create new Option (branch+worktree) from a selected checkpoint's commit hash. Push immediately (Rule A). |
| F12 | **PR creation** | Create a PR from an Option branch. Primary: `gh pr create` via the command runner. Fallback: open GitHub compare URL in browser. Persist PR URL/number on the Option. |
| F13 | **Persistence** | Persist app state locally as JSON files. Store: repos, experiments, options, turns, checkpoint commit hashes, ports, statuses, PR URLs. |

### 3.2 Non-Functional Requirements

- **macOS 13+ (Ventura)** minimum deployment target.
- **No in-app LLM inference.** The app is a harness for external tools.
- **Direct distribution** for MVP (no App Store sandboxing). Signed with Developer ID.
- **Robust streaming logs** and clear error messages for all git/process operations.
- **Safe command execution:** Never construct shell strings. Always use `Process` with explicit `executableURL` + `arguments`. Sanitize all slugs and branch names.

### 3.3 Non-Requirements

- No custom agent harness (system prompts, tool calling) inside the app.
- No collaborative web gallery.
- No merge automation in Phase 1 (closing sibling Options on merge is deferred).
- No cross-platform support.
- No in-app diff viewer (use external tools or GitHub).

---

## 4. Technical Choices

| Area | Choice | Rationale |
|------|--------|-----------|
| **UI** | SwiftUI + AppKit bridges | SwiftUI for layout and state; `NSViewRepresentable` for WKWebView; `NSWindow` access where needed for multi-window. |
| **Web preview** | WKWebView via `NSViewRepresentable` | Standard macOS web view; works with localhost. |
| **Process execution** | `Foundation.Process` + `Pipe` | Stream stdout/stderr line-by-line via `FileHandle.readabilityHandler`. |
| **Persistence** | JSON files (Codable) | Simpler than SwiftData for this data shape (nested, not relational). Easy to inspect/debug. Single file per repo: `~/.spur/<repoId>.json`. |
| **Terminal Phase 1** | Command Runner + "Open in Terminal.app" | `Process`-based command execution with streaming output in a SwiftUI view. "Open in Terminal.app" via `NSWorkspace` / AppleScript. |
| **Terminal Phase 2** | PTY via `forkpty(3)` | Planned. Provides full terminal emulation. |
| **PR creation** | `gh` CLI | Run `gh pr create` as a `Process`. Fallback: open `https://github.com/<owner>/<repo>/compare/<branch>` in browser. |

---

## 5. Repository Scaffold

```
Spur/
├── plan.md                          # This file
├── agents.md                        # Multi-model collaboration guide
├── .gitignore
├── Spur.xcodeproj/                  # Xcode project (generated)
├── Spur/
│   ├── SpurApp.swift                # @main App entry point
│   ├── Info.plist
│   ├── Assets.xcassets/
│   │
│   ├── Models/                      # Data models (Codable structs)
│   │   ├── Repo.swift
│   │   ├── Experiment.swift
│   │   ├── Option.swift
│   │   ├── Turn.swift
│   │   └── AppState.swift           # Top-level state container
│   │
│   ├── Services/                    # Business logic / side effects
│   │   ├── GitService.swift         # Branch, worktree, commit, push operations
│   │   ├── DevServerService.swift   # Start/stop dev servers, port allocation
│   │   ├── ProcessRunner.swift      # Safe Process + Pipe execution with streaming
│   │   ├── PersistenceService.swift # JSON read/write
│   │   ├── PRService.swift          # GitHub PR creation (gh CLI + browser fallback)
│   │   └── TerminalService.swift    # "Open in Terminal.app" helper
│   │
│   ├── ViewModels/                  # ObservableObject view models
│   │   ├── RepoViewModel.swift
│   │   ├── ExperimentViewModel.swift
│   │   ├── OptionViewModel.swift
│   │   └── CommandRunnerViewModel.swift
│   │
│   ├── Views/                       # SwiftUI views
│   │   ├── Sidebar/
│   │   │   ├── SidebarView.swift
│   │   │   ├── RepoPickerView.swift
│   │   │   └── ExperimentListView.swift
│   │   │
│   │   ├── Main/
│   │   │   ├── OptionTabBar.swift          # Tab strip for Options
│   │   │   ├── OptionDetailView.swift      # Selected option: preview + logs + turns
│   │   │   ├── WebPreviewView.swift        # WKWebView wrapper
│   │   │   └── TurnListView.swift          # Checkpoint list + fork button
│   │   │
│   │   ├── CommandRunner/
│   │   │   ├── CommandRunnerView.swift      # Command input + streaming output
│   │   │   └── LogOutputView.swift         # Scrollable log display
│   │   │
│   │   └── Dialogs/
│   │       ├── NewExperimentSheet.swift
│   │       ├── NewOptionSheet.swift
│   │       ├── ForkFromCheckpointSheet.swift
│   │       └── CreatePRSheet.swift
│   │
│   └── Utilities/
│       ├── SlugGenerator.swift       # Sanitize names to valid branch slugs
│       ├── PortAllocator.swift       # Find available ports
│       └── Constants.swift           # App-wide constants
│
└── SpurTests/
    ├── GitServiceTests.swift
    ├── DevServerServiceTests.swift
    ├── ProcessRunnerTests.swift
    ├── PersistenceServiceTests.swift
    ├── SlugGeneratorTests.swift
    └── PortAllocatorTests.swift
```

---

## 6. Persistence Schema

All state for a repo is stored in a single JSON file at `~/.spur/<repoId>.json`.

```json
{
  "repoId": "uuid",
  "repoPath": "/Users/me/projects/my-app",
  "baseBranch": "main",
  "experiments": [
    {
      "id": "uuid",
      "name": "Color Study",
      "slug": "color-study",
      "createdAt": "2026-03-07T10:00:00Z",
      "optionIds": ["uuid-1", "uuid-2"]
    }
  ],
  "options": [
    {
      "id": "uuid-1",
      "experimentId": "uuid",
      "name": "Warm Palette",
      "slug": "warm-palette",
      "branchName": "exp/color-study/warm-palette",
      "worktreePath": "/Users/me/projects/spur-worktrees/color-study--warm-palette",
      "port": 3001,
      "status": "running",
      "forkedFromCommit": null,
      "prURL": null,
      "prNumber": null,
      "turns": [
        {
          "id": "uuid-t1",
          "number": 1,
          "label": "Initial layout",
          "startCommit": "abc1230",
          "endCommit": "abc1234",
          "commitRange": ["abc1231", "abc1232", "abc1233", "abc1234"],
          "createdAt": "2026-03-07T10:05:00Z"
        }
      ]
    }
  ]
}
```

---

## 7. Phases of Build

### Phase 1 — Foundation: Repo, Models, Persistence

**Goal:** Establish the data layer and project skeleton. A user can select a repo and see it persisted.

**Deliverables:**
- Xcode project with folder structure from §5.
- `Repo`, `Experiment`, `Option`, `Turn`, `AppState` model structs (Codable).
- `PersistenceService` — read/write JSON to `~/.spur/`.
- `SlugGenerator` and `PortAllocator` utilities.
- `RepoPickerView` with `NSOpenPanel` for directory selection.
- Unit tests for models, persistence, slug generation, port allocation.

**Acceptance Criteria:**
- [ ] App launches, user can select a repo directory via file picker.
- [ ] Repo path is persisted to JSON and restored on relaunch.
- [ ] `SlugGenerator` produces valid git branch name segments (lowercase, alphanumeric, hyphens, max 50 chars).
- [ ] `PortAllocator` returns available ports in the 3001–3999 range.
- [ ] All unit tests pass.

**Key Risks / Mitigations:**
- Risk: JSON schema changes break existing data. Mitigation: version the schema; add migration logic early.
- Risk: Port conflicts at runtime. Mitigation: `PortAllocator` checks `bind()` before returning a port.

**Best-suited role:** Builder (initial scaffold) + Test/QA (unit tests).

---

### Phase 2 — Git Core: Branches + Worktrees

**Goal:** Implement `GitService` — branch creation, worktree creation (both modes), worktree removal, push, and worktree listing.

**Deliverables:**
- `GitService` with methods:
  - `createBranchAndWorktree(from: .main | .commit(hash), branchName:, worktreePath:)`
  - `removeWorktree(path:)`
  - `listWorktrees() -> [WorktreeInfo]`
  - `push(branch:)`
  - `getCurrentCommitHash(in worktreePath:) -> String`
  - `getCommitsSince(hash:, in worktreePath:) -> [String]`
- `ProcessRunner` — safe process execution with streaming output.
- Unit/integration tests for `GitService` (using a temp git repo).

**Acceptance Criteria:**
- [ ] Can create a branch+worktree from `main` (Mode A).
- [ ] Can create a branch+worktree from a specific commit hash (Mode B).
- [ ] Branch is pushed to origin after creation.
- [ ] Can remove a worktree safely.
- [ ] `listWorktrees()` returns accurate data that can reconcile with persisted Options.
- [ ] `ProcessRunner` streams stdout/stderr line-by-line and reports exit codes.
- [ ] No shell string construction anywhere — all uses are `executableURL` + `arguments`.

**Key Risks / Mitigations:**
- Risk: `git worktree add` fails if branch already exists. Mitigation: check branch existence first; surface clear error.
- Risk: Worktree directory already exists on disk. Mitigation: check before creating; offer to reconcile.

**Best-suited role:** Builder (core implementation) + Reviewer (security review of process execution).

---

### Phase 3 — Experiment + Option UI

**Goal:** Build the primary UI: sidebar with experiments, tab bar for Options, creating new Experiments and Options.

**Deliverables:**
- `SidebarView` with experiment list, repo info.
- `ExperimentListView` with add/select experiments.
- `OptionTabBar` showing Options as tabs within the selected Experiment.
- `NewExperimentSheet` and `NewOptionSheet` dialogs.
- `ExperimentViewModel` and `OptionViewModel` wiring models → views.
- Creating a new Option triggers `GitService.createBranchAndWorktree` and pushes (Rule A).

**Acceptance Criteria:**
- [ ] User can create an Experiment with a name.
- [ ] User can create an Option within an Experiment; branch+worktree are created and pushed.
- [ ] Options appear as tabs; selecting a tab switches the detail view.
- [ ] State is persisted and survives app relaunch.
- [ ] Branch naming follows `exp/<experimentId>/<optionSlug>` convention.

**Key Risks / Mitigations:**
- Risk: UI state and persisted state drift. Mitigation: single source of truth in view models; persist on every mutation.
- Risk: Git operations are slow and block UI. Mitigation: run all git operations on background threads via Swift concurrency (`Task`).

**Best-suited role:** Builder (UI) + Reviewer (state management review).

---

### Phase 4 — Dev Server + Live Preview

**Goal:** Start/stop Next.js dev servers per Option and display live preview in WKWebView.

**Deliverables:**
- `DevServerService`:
  - `start(worktreePath:, port:) -> AsyncStream<String>` (log lines).
  - `stop(port:)` — send SIGTERM, then SIGKILL after timeout.
  - Track running processes by Option ID.
- `WebPreviewView` — WKWebView wrapper loading `http://localhost:<port>`.
- `OptionDetailView` combining preview + log output + turn list.
- `LogOutputView` — scrollable, auto-scrolling log display.

**Acceptance Criteria:**
- [ ] Starting an Option's dev server runs `npm run dev -- --port <port>` in the worktree directory.
- [ ] Logs stream in real-time to `LogOutputView`.
- [ ] WKWebView displays the running app; reloads on demand.
- [ ] Stopping an Option kills the dev server process and all child processes.
- [ ] Multiple Options can run dev servers concurrently on different ports.
- [ ] Switching tabs updates the preview to the selected Option's port.

**Key Risks / Mitigations:**
- Risk: Zombie processes if app crashes. Mitigation: use process groups; clean up on `applicationWillTerminate`.
- Risk: WKWebView caching stale content. Mitigation: disable caching or add cache-busting reload.
- Risk: `npm run dev` command varies by project. Mitigation: make dev command configurable per repo (default: `npm run dev`).

**Best-suited role:** Builder (process management) + Integrator (connecting UI to services).

---

### Phase 5 — Turns, Checkpoints, and Forking

**Goal:** Implement the Turn/Checkpoint workflow and "fork from checkpoint" — the defining feature.

**Deliverables:**
- Turn creation UI in `TurnListView`.
- "Capture Checkpoint" action:
  - Detect uncommitted changes → commit them (for tools that don't commit).
  - Detect new commits since turn start → record commit range (for tools that commit).
  - Record final commit hash on the Turn.
  - Push branch (Rule A).
- `ForkFromCheckpointSheet` — select a Turn, create a new Option at that commit.
- `GitService.createBranchAndWorktree(from: .commit(turn.endCommit), ...)`.

**Acceptance Criteria:**
- [ ] User can start a Turn (records starting HEAD).
- [ ] "Capture Checkpoint" correctly handles both auto-commit and commit-range scenarios.
- [ ] After checkpoint, branch is pushed to origin.
- [ ] User can fork from any checkpoint; new Option appears with correct code state.
- [ ] Forked Option's worktree matches the filesystem state of the checkpoint commit.
- [ ] Forked Option's branch is pushed immediately.

**Key Risks / Mitigations:**
- Risk: Uncommitted changes in worktree when capturing checkpoint. Mitigation: stage all, commit with descriptive message `[spur] Checkpoint: <turn label>`.
- Risk: User forks from a commit that no longer exists (force-push). Mitigation: verify commit hash exists before forking; show error if not.

**Best-suited role:** Builder (core logic) + Test/QA (complex state transitions).

---

### Phase 6 — Command Runner + PR Creation

**Goal:** Implement the command runner panel (Phase 1 terminal) and PR creation from Options.

**Deliverables:**
- `CommandRunnerView` — text input for commands, streaming output display.
- `CommandRunnerViewModel` — runs commands via `ProcessRunner` in the Option's worktree.
- "Open in Terminal.app" button via `TerminalService`.
- `PRService`:
  - Primary: run `gh pr create --base main --head <branch> --title <title>` via `ProcessRunner`.
  - Fallback: open `https://github.com/<owner>/<repo>/compare/<branch>?expand=1` in browser.
  - Parse and persist PR URL/number on the Option.
- `CreatePRSheet` — dialog for title, body, and create action.

**Acceptance Criteria:**
- [ ] User can type and run commands in the Command Runner; output streams in real-time.
- [ ] Commands execute in the Option's worktree directory (cwd set correctly).
- [ ] "Open in Terminal.app" opens Terminal.app with `cd` to worktree path.
- [ ] User can create a PR from an Option; PR URL is persisted and displayed.
- [ ] If `gh` is not installed, falls back to opening browser.
- [ ] Command execution uses `executableURL` + `arguments`, never shell strings.

**Key Risks / Mitigations:**
- Risk: User runs destructive commands (e.g., `rm -rf /`). Mitigation: commands run in worktree directory; add optional confirmation for destructive patterns (later enhancement). For MVP, trust the user.
- Risk: `gh` CLI not authenticated. Mitigation: detect auth failure and show helpful error message with `gh auth login` instructions.

**Best-suited role:** Builder (command runner) + Integrator (PR flow wiring).

---

### Phase 7 — Polish, Error Handling, and Testing

**Goal:** Harden the app: error handling, edge cases, UI polish, comprehensive testing.

**Deliverables:**
- Global error handling: surface git errors, process failures, and disk errors as user-visible alerts.
- Worktree reconciliation: on app launch, reconcile persisted Options with actual worktrees on disk.
- Graceful shutdown: stop all dev servers on app quit.
- UI polish: loading states, empty states, keyboard shortcuts (Cmd+T new option, Cmd+W close tab, Cmd+R reload preview).
- Integration tests for key workflows (create experiment → create option → start server → capture checkpoint → fork).
- Accessibility audit (VoiceOver labels on key controls).

**Acceptance Criteria:**
- [ ] App handles missing worktree directories gracefully (marks Option as "detached").
- [ ] App handles git push failures with retry and clear error messages.
- [ ] All dev servers are stopped on app quit.
- [ ] No crashes on edge cases: empty repo, no remote, no `gh` CLI, port in use.
- [ ] Keyboard shortcuts work as specified.
- [ ] All tests pass; no warnings in Xcode.

**Key Risks / Mitigations:**
- Risk: Edge cases not discovered until real usage. Mitigation: manual testing checklist in addition to automated tests.
- Risk: Reconciliation logic is complex. Mitigation: clearly define states (active, detached, orphaned) and transitions.

**Best-suited role:** Refactorer (error handling) + Test/QA (comprehensive testing) + Reviewer (final review).

---

## 8. Data Flow Diagram

```
User Action
    │
    ▼
SwiftUI View  ──▶  ViewModel  ──▶  Service (Git/DevServer/PR/Persistence)
    ▲                  │                        │
    │                  ▼                        ▼
    └──── @Published state ◀──── Result / AsyncStream
```

All git and process operations are async. ViewModels expose `@Published` properties. Services are injected as dependencies for testability.

---

## 9. Appendix: Later

These items are **not** in scope for the phases above but are worth tracking:

- **Merge automation:** When one Option's PR is merged, prompt to close/archive sibling Options.
- **Diff viewer:** In-app side-by-side diff between two Options (or between an Option and main).
- **Experiment templates:** Pre-configured experiment setups (e.g., "A/B color test" with two Options).
- **Remote worktree sync:** Support for shallow clones or partial checkouts for large repos.
- **PTY terminal (Phase 2):** Full embedded terminal emulator using `forkpty(3)`.
- **Theming:** Dark/light mode parity; custom accent colors per Experiment.
- **Export:** Export experiment results (screenshots, PR links, notes) as a report.
