# Spur — Multi-Agent Collaboration Guide

> **Source of truth:** [`plan.md`](plan.md) contains the full engineering plan, requirements, phases, and repository scaffold. This document defines how multiple coding models collaborate to build Spur.

---

## 1. Roles

Four roles operate on this codebase. A single model session assumes one role at a time.

| Role | Responsibility | When to use |
|------|---------------|-------------|
| **Builder** | Writes new code: models, services, views, view models. Implements phase deliverables. | Starting a new phase or feature. Most prompt sessions are Builder sessions. |
| **Reviewer** | Reviews code for correctness, security, architecture adherence, and consistency with `plan.md`. Does NOT write new features. | After a Builder completes a deliverable. Every PR must have a Reviewer pass. |
| **Refactorer** | Improves existing code: error handling, performance, code organization, DRY. Does NOT add features. | After Phase 4+, or when tech debt accumulates. Phase 7 is primarily Refactorer work. |
| **Test/QA** | Writes and runs tests. Validates acceptance criteria. Reports bugs as issues. | After each phase deliverable. Owns the test suite. |

### Role Rules

1. A session must declare its role at the start.
2. A Builder session must not review its own output — a separate Reviewer session must follow.
3. A Refactorer must not change public APIs without Builder + Reviewer approval.
4. Test/QA must validate every acceptance criterion listed in `plan.md` for the relevant phase.

---

## 2. Workflow

Every change follows this strict workflow:

```
1. CLAIM    → Declare role + phase + task
2. BRANCH   → Create or switch to feature branch
3. BUILD    → Implement changes
4. TEST     → Run tests, verify acceptance criteria
5. COMMIT   → Commit with conventional message
6. REVIEW   → Reviewer session evaluates
7. MERGE    → Merge to development branch
```

### 2.1 Before Starting Work

Every session must:

1. Read `plan.md` §7 (Phases) for the target phase.
2. Identify the specific deliverables being worked on.
3. Check the current state of the codebase (`git log --oneline -10`, check existing files).
4. Reference the phase number and deliverable in all commits.

### 2.2 Change Checklist

Every change (commit or PR) must satisfy:

- [ ] References a phase number from `plan.md` (e.g., "Phase 2").
- [ ] Addresses a specific deliverable listed in that phase.
- [ ] Does not introduce features outside the current phase scope.
- [ ] Follows the code conventions in §3.
- [ ] Includes or updates tests for changed logic.
- [ ] Does not break existing tests.
- [ ] Has been reviewed by a Reviewer session (for PRs).

---

## 3. Conventions

### 3.1 Branch Naming (for development branches, NOT experiment branches)

Development branches for building Spur itself:

```
<role>/<phase>/<description>
```

Examples:
- `builder/phase-2/git-service`
- `refactorer/phase-7/error-handling`
- `testqa/phase-2/git-service-tests`

### 3.2 Commit Message Format

```
[Phase N] <type>: <short description>

<optional body explaining why>
```

**Types:** `feat`, `fix`, `refactor`, `test`, `docs`, `chore`

Examples:
```
[Phase 2] feat: implement GitService branch+worktree creation

Supports both "from main" and "from commit" modes per plan.md §2.2.

[Phase 4] fix: kill child processes on dev server stop

Process groups ensure npm child processes are terminated.

[Phase 1] test: add SlugGenerator edge case tests
```

### 3.3 Code Style

| Rule | Detail |
|------|--------|
| **Naming** | Swift API design guidelines. Types are `PascalCase`, properties/methods are `camelCase`. |
| **File organization** | One primary type per file. File name matches the type name. |
| **Access control** | Mark everything `private` or `internal` unless it needs to be `public`. Services expose a protocol. |
| **Concurrency** | Use Swift concurrency (`async/await`, `Task`, `AsyncStream`). No completion handlers. No `DispatchQueue` unless wrapping legacy API. |
| **Error handling** | Define typed errors per service (e.g., `GitServiceError`). Never silently catch errors. Surface to user via `@Published var error: Error?` on view models. |
| **Logging** | Use `os.Logger` with subsystem `"com.spur.app"` and per-service category. Log at `.debug` for routine operations, `.error` for failures. |
| **Process execution** | **NEVER** use `Process.launchPath` with a shell string. Always set `executableURL` and `arguments` array. Use `/usr/bin/env` to resolve tool paths if needed. |
| **Imports** | One import per line, sorted alphabetically. No `@testable import` outside test targets. |

### 3.4 PR Checklist

Every PR description must include:

```markdown
## Phase
Phase N — <phase name>

## Deliverables addressed
- [ ] <deliverable from plan.md>

## Testing
- [ ] Unit tests added/updated
- [ ] Acceptance criteria verified: <list specific criteria>
- [ ] Manual testing performed: <describe>

## Security
- [ ] No shell string construction
- [ ] No hardcoded secrets or paths
- [ ] Input sanitization for user-provided names
```

### 3.5 Error Handling Pattern

```
Service method throws typed error
    → ViewModel catches, sets @Published error property
        → View displays alert/banner from error property
```

Never crash on recoverable errors. Never show raw error messages to users — map to human-readable strings.

### 3.6 Logging Pattern

```swift
import os

private let logger = Logger(subsystem: "com.spur.app", category: "GitService")

func createBranch(name: String) async throws {
    logger.debug("Creating branch: \(name)")
    // ...
    logger.info("Branch created and pushed: \(name)")
}
```

---

## 4. Prompt Packets

When delegating work to a coding model, construct a **prompt packet** with these sections:

```markdown
# Prompt Packet: <title>

## Role
Builder | Reviewer | Refactorer | Test/QA

## Phase
Phase N — <phase name>

## Context
- Read: plan.md §<section>
- Read: <list of files the model must read before starting>
- Current state: <brief description of what exists>

## Task
<Specific, actionable description of what to build/review/test>

## Constraints
- <Constraint 1, e.g., "Do not modify public API of GitService">
- <Constraint 2, e.g., "Use AsyncStream for log streaming">
- <Constraint 3, e.g., "Follow error handling pattern from agents.md §3.5">

## Acceptance Criteria
- [ ] <Criterion from plan.md>
- [ ] <Additional criterion if needed>

## Output
- Files created/modified: <list>
- Tests: <what tests to write/run>
- Compile check: `xcodebuild -scheme Spur -destination 'platform=macOS' build`
- Test check: `xcodebuild -scheme Spur -destination 'platform=macOS' test`
```

---

## 5. Prompt Sequence

The following sequence breaks the Spur build into discrete, narrowly-scoped prompts. Each prompt corresponds to a phase deliverable and is designed to be handed to a coding model as a self-contained unit.

---

### Prompt 1: Project Skeleton + Models

**Role:** Builder
**Phase:** Phase 1 — Foundation

**Inputs required:**
- `plan.md` §5 (Repository Scaffold), §6 (Persistence Schema)
- `agents.md` §3 (Conventions)

**Task:**
Create the Xcode project and implement all data models.
- Create the Xcode project `Spur` with the folder structure from `plan.md` §5.
- Implement `Repo`, `Experiment`, `Option`, `Turn`, `AppState` as `Codable` structs with `Identifiable` conformance.
- Implement `SlugGenerator` (sanitize to lowercase alphanumeric + hyphens, max 50 chars).
- Implement `PortAllocator` (find available port in 3001–3999 range using `bind()` check).
- Add placeholder files for all Services and ViewModels (empty structs/classes with `// TODO` markers).

**Outputs expected:**
- All files in `Spur/Models/`, `Spur/Utilities/`
- Placeholder files in `Spur/Services/`, `Spur/ViewModels/`, `Spur/Views/`
- `SpurApp.swift` with minimal `@main` app

**Compile/run check:**
- `xcodebuild -scheme Spur -destination 'platform=macOS' build` succeeds.

---

### Prompt 2: Persistence Service + Repo Picker

**Role:** Builder
**Phase:** Phase 1 — Foundation

**Inputs required:**
- `plan.md` §6 (Persistence Schema)
- `Spur/Models/` (from Prompt 1)

**Task:**
- Implement `PersistenceService`: read/write `AppState` as JSON to `~/.spur/<repoId>.json`.
- Handle first-run (directory creation), corrupt file recovery (backup + reset), and schema versioning.
- Implement `RepoPickerView` with `NSOpenPanel` for directory selection.
- Implement `RepoViewModel` that loads/saves repo state via `PersistenceService`.
- Wire into `SpurApp.swift`: show repo picker if no repo selected, otherwise show main view.

**Outputs expected:**
- `Spur/Services/PersistenceService.swift`
- `Spur/Views/Sidebar/RepoPickerView.swift`
- `Spur/ViewModels/RepoViewModel.swift`
- Updated `SpurApp.swift`

**Compile/run check:**
- App launches, shows repo picker, persists selection to `~/.spur/`, restores on relaunch.

---

### Prompt 3: Persistence + Models Unit Tests

**Role:** Test/QA
**Phase:** Phase 1 — Foundation

**Inputs required:**
- `Spur/Models/`, `Spur/Services/PersistenceService.swift`, `Spur/Utilities/` (from Prompts 1–2)

**Task:**
- Write unit tests for all models (encoding/decoding roundtrips, edge cases).
- Write unit tests for `SlugGenerator` (special characters, length limits, empty input, unicode).
- Write unit tests for `PortAllocator` (port availability, range bounds).
- Write unit tests for `PersistenceService` (write, read, missing directory, corrupt file).

**Outputs expected:**
- `SpurTests/PersistenceServiceTests.swift`
- `SpurTests/SlugGeneratorTests.swift`
- `SpurTests/PortAllocatorTests.swift`
- `SpurTests/ModelTests.swift` (new file for roundtrip tests)

**Compile/run check:**
- `xcodebuild -scheme Spur -destination 'platform=macOS' test` — all tests pass.

---

### Prompt 4: ProcessRunner + GitService

**Role:** Builder
**Phase:** Phase 2 — Git Core

**Inputs required:**
- `plan.md` §2 (Branch + Worktree Philosophy)
- `Spur/Models/Option.swift`, `Spur/Utilities/SlugGenerator.swift` (from Prompt 1)

**Task:**
- Implement `ProcessRunner`:
  - `run(executable:, arguments:, workingDirectory:, environment:) async throws -> ProcessResult`
  - `stream(executable:, arguments:, workingDirectory:) -> AsyncStream<ProcessOutput>` (line-by-line stdout/stderr)
  - `ProcessResult` = `{ stdout: String, stderr: String, exitCode: Int32 }`
  - `ProcessOutput` = enum `{ case stdout(String), case stderr(String), case exit(Int32) }`
  - **CRITICAL:** Use `Process.executableURL` + `arguments` array. Never shell strings.
- Implement `GitService`:
  - `createBranchAndWorktree(repoPath:, branchName:, worktreePath:, from: BranchSource)` where `BranchSource = .main(String) | .commit(String)`
  - `removeWorktree(repoPath:, worktreePath:)`
  - `listWorktrees(repoPath:) -> [WorktreeInfo]`
  - `push(repoPath:, branch:)`
  - `getCurrentHead(worktreePath:) -> String`
  - `getCommitsSince(hash:, worktreePath:) -> [String]`
  - `hasUncommittedChanges(worktreePath:) -> Bool`
  - `commitAll(worktreePath:, message:) -> String` (returns commit hash)
  - All methods resolve `git` via `/usr/bin/env git` or `/usr/bin/git`.

**Outputs expected:**
- `Spur/Services/ProcessRunner.swift`
- `Spur/Services/GitService.swift`

**Compile/run check:**
- `xcodebuild -scheme Spur -destination 'platform=macOS' build` succeeds.

---

### Prompt 5: GitService Tests

**Role:** Test/QA
**Phase:** Phase 2 — Git Core

**Inputs required:**
- `Spur/Services/GitService.swift`, `Spur/Services/ProcessRunner.swift` (from Prompt 4)

**Task:**
- Write integration tests using a temporary git repo (create in `setUp`, delete in `tearDown`).
- Test: create branch+worktree from main, create branch+worktree from specific commit, remove worktree, list worktrees, push (using a bare repo as remote), commit detection, commit range detection.
- Test: `ProcessRunner` with simple commands (e.g., `/usr/bin/echo`), error handling for nonexistent executables, streaming output.

**Outputs expected:**
- `SpurTests/GitServiceTests.swift`
- `SpurTests/ProcessRunnerTests.swift`

**Compile/run check:**
- `xcodebuild -scheme Spur -destination 'platform=macOS' test` — all tests pass.

---

### Prompt 6: Experiment + Option UI

**Role:** Builder
**Phase:** Phase 3 — UI

**Inputs required:**
- `plan.md` §5 (Views section), §7 Phase 3 deliverables
- All Models, `GitService`, `PersistenceService` (from prior prompts)

**Task:**
- Implement `SidebarView`: shows selected repo info, list of experiments, "New Experiment" button.
- Implement `ExperimentListView`: selectable list of experiments.
- Implement `OptionTabBar`: horizontal tab strip of Options within selected experiment.
- Implement `NewExperimentSheet`: name input → creates Experiment, persists.
- Implement `NewOptionSheet`: name input, source selector (from main / from checkpoint) → calls `GitService`, persists.
- Implement `OptionDetailView`: placeholder content (preview and logs come in Phase 4).
- Implement `ExperimentViewModel` and `OptionViewModel`.
- Wire NavigationSplitView: sidebar (experiments) | detail (option tabs + detail).

**Outputs expected:**
- All files in `Spur/Views/Sidebar/`, `Spur/Views/Main/` (except `WebPreviewView`), `Spur/Views/Dialogs/NewExperimentSheet.swift`, `Spur/Views/Dialogs/NewOptionSheet.swift`
- `Spur/ViewModels/ExperimentViewModel.swift`, `Spur/ViewModels/OptionViewModel.swift`

**Compile/run check:**
- App launches, user can create experiment, create option (branch+worktree created on disk), switch tabs.

---

### Prompt 7: Dev Server + Web Preview

**Role:** Builder
**Phase:** Phase 4 — Dev Server + Preview

**Inputs required:**
- `plan.md` §7 Phase 4 deliverables
- `ProcessRunner`, `OptionViewModel`, `OptionDetailView` (from prior prompts)

**Task:**
- Implement `DevServerService`:
  - `start(worktreePath:, port:, command:) -> AsyncStream<String>`
  - `stop(optionId:)` — SIGTERM, then SIGKILL after 5s timeout.
  - Track running processes by option ID. Use process groups (`setpgid`) to kill child processes.
  - Clean up all processes on `deinit` / app termination.
- Implement `WebPreviewView`: `NSViewRepresentable` wrapping `WKWebView`, loading `http://localhost:<port>`.
- Implement `LogOutputView`: scrollable text view with auto-scroll, monospace font.
- Update `OptionDetailView`: split view with preview on top, logs on bottom.
- Wire start/stop buttons in `OptionViewModel`.

**Outputs expected:**
- `Spur/Services/DevServerService.swift`
- `Spur/Views/Main/WebPreviewView.swift`
- `Spur/Views/CommandRunner/LogOutputView.swift`
- Updated `Spur/Views/Main/OptionDetailView.swift`
- `SpurTests/DevServerServiceTests.swift`

**Compile/run check:**
- App can start a dev server for an Option, display logs, show preview in WKWebView, stop server cleanly.

---

### Prompt 8: Turns, Checkpoints, and Forking

**Role:** Builder
**Phase:** Phase 5 — Turns + Forking

**Inputs required:**
- `plan.md` §2 (Philosophy), §7 Phase 5 deliverables
- `GitService`, `OptionViewModel`, `TurnListView` placeholder (from prior prompts)

**Task:**
- Implement Turn creation: "New Turn" button records starting HEAD hash and timestamp.
- Implement "Capture Checkpoint":
  - Check `GitService.hasUncommittedChanges()` → if yes, `commitAll(message: "[spur] Checkpoint: <label>")`.
  - Check `GitService.getCommitsSince(startCommit)` → record commit range.
  - Record `endCommit` hash on Turn.
  - Push branch (Rule A).
- Implement `TurnListView`: list of turns with commit info, "Fork from here" button.
- Implement `ForkFromCheckpointSheet`: name input → `GitService.createBranchAndWorktree(from: .commit(turn.endCommit))`.
- Persist all turn data.

**Outputs expected:**
- `Spur/Views/Main/TurnListView.swift`
- `Spur/Views/Dialogs/ForkFromCheckpointSheet.swift`
- Updated `Spur/ViewModels/OptionViewModel.swift`
- Updated `Spur/Models/Turn.swift` (if needed)

**Compile/run check:**
- Full flow: create option → start turn → run commands → capture checkpoint → fork from checkpoint → new option at correct commit.

---

### Prompt 9: Command Runner + PR Creation

**Role:** Builder
**Phase:** Phase 6 — Command Runner + PR

**Inputs required:**
- `plan.md` §7 Phase 6 deliverables
- `ProcessRunner`, `OptionViewModel` (from prior prompts)

**Task:**
- Implement `CommandRunnerView`: text field for command input, run button, streaming output area.
- Implement `CommandRunnerViewModel`: parse command string into executable + arguments (split on whitespace, respect quotes), run via `ProcessRunner` in worktree cwd.
- Implement `TerminalService.openInTerminal(worktreePath:)` — opens Terminal.app via AppleScript or `NSWorkspace`.
- Implement `PRService`:
  - `createPR(repoPath:, branch:, title:, body:) async throws -> PRURL`
  - Try `gh pr create` first. Parse output for PR URL.
  - If `gh` not found, open `https://github.com/<remote-owner>/<remote-repo>/compare/<branch>?expand=1` in browser.
  - Parse remote URL from `git remote get-url origin`.
- Implement `CreatePRSheet`: title + body inputs, create button, displays result URL.
- Persist PR URL/number on Option.

**Outputs expected:**
- `Spur/Views/CommandRunner/CommandRunnerView.swift`
- `Spur/ViewModels/CommandRunnerViewModel.swift`
- `Spur/Services/TerminalService.swift`
- `Spur/Services/PRService.swift`
- `Spur/Views/Dialogs/CreatePRSheet.swift`

**Compile/run check:**
- Command runner executes commands in worktree. PR creation works via `gh` or opens browser.

---

### Prompt 10: Error Handling + Reconciliation

**Role:** Refactorer
**Phase:** Phase 7 — Polish

**Inputs required:**
- `plan.md` §7 Phase 7 deliverables
- All Services and ViewModels (from prior prompts)

**Task:**
- Define typed error enums for each service (`GitServiceError`, `DevServerError`, `PRServiceError`, `PersistenceError`).
- Add error → user-facing message mapping.
- Implement worktree reconciliation on app launch: compare persisted Options vs `git worktree list`; mark missing as "detached".
- Implement graceful shutdown: `applicationWillTerminate` stops all dev servers.
- Add loading states to all async operations (view models expose `isLoading` flags).
- Add empty states to all list views.

**Outputs expected:**
- Updated all files in `Spur/Services/` (typed errors)
- Updated all files in `Spur/ViewModels/` (error handling, loading states)
- Updated list views (empty states)
- New: `Spur/Services/ReconciliationService.swift`

**Compile/run check:**
- App handles missing worktrees, failed git operations, and missing `gh` CLI gracefully. No crashes.

---

### Prompt 11: Integration Tests + Final QA

**Role:** Test/QA
**Phase:** Phase 7 — Polish

**Inputs required:**
- Full codebase (from prior prompts)
- `plan.md` §7 Phase 7 acceptance criteria

**Task:**
- Write integration tests for end-to-end workflows:
  - Create experiment → create option → start dev server → capture checkpoint → fork → create PR.
  - Reconciliation: delete worktree on disk, launch app, verify "detached" state.
  - Error paths: invalid repo, port in use, git push failure.
- Verify all acceptance criteria from every phase.
- Report any bugs found as TODO comments with `// BUG:` prefix.

**Outputs expected:**
- `SpurTests/IntegrationTests.swift`
- `SpurTests/ReconciliationTests.swift`
- Updated test files as needed

**Compile/run check:**
- `xcodebuild -scheme Spur -destination 'platform=macOS' test` — all tests pass.

---

### Prompt 12: Final Review

**Role:** Reviewer
**Phase:** All phases

**Inputs required:**
- Full codebase
- `plan.md`, `agents.md`

**Task:**
- Review every file for:
  - Security: no shell string construction, no hardcoded paths, input sanitization.
  - Architecture: separation of concerns, no view logic in services, no service logic in views.
  - Consistency: naming, error handling pattern, logging pattern.
  - Completeness: all `plan.md` requirements addressed.
- Produce a review report as PR comments or a `REVIEW.md` file.

**Outputs expected:**
- `REVIEW.md` with findings and recommendations
- Fix PRs for any critical issues found

**Compile/run check:**
- `xcodebuild -scheme Spur -destination 'platform=macOS' build` succeeds.
- `xcodebuild -scheme Spur -destination 'platform=macOS' test` — all tests pass.
