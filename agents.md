# Spur — Multi-Agent Collaboration Guide

> **Source of truth:** [`plan.md`](./plan.md) governs all product decisions, requirements, data models, and phase definitions.
> This file governs **how** coding agents collaborate, communicate, and ship changes.
> When `plan.md` and `agents.md` conflict, `plan.md` wins.

---

## Table of Contents

1. [Roles](#1-roles)
2. [Workflow Protocol](#2-workflow-protocol)
3. [Conventions](#3-conventions)
   - 3.1 Branch Naming
   - 3.2 Commit Message Format
   - 3.3 PR Checklist
   - 3.4 Code Style
   - 3.5 Logging
   - 3.6 Error Handling
4. [Prompt Packet Format](#4-prompt-packet-format)
5. [Prompt Sequence](#5-prompt-sequence)

---

## 1. Roles

Every change to the codebase is made by an agent occupying exactly one role. Roles are not permanently assigned to a model; a model may occupy different roles in different sessions. The active role must be stated in every PR description and commit message prefix.

### Builder

**Responsibility:** Write new, net-new production code that implements a phase deliverable.

- Works from a narrow, phase-scoped prompt packet (see §4).
- May create new files; may modify existing files only if required by the deliverable.
- Must not refactor code outside the scope of the deliverable.
- Must write unit tests for any logic that has no existing test coverage.
- Must not mark a phase complete until all acceptance criteria in `plan.md §10` pass.

### Reviewer

**Responsibility:** Audit a Builder's output before it merges.

- Reads the diff against the phase's acceptance criteria in `plan.md`.
- Checks: correctness, security (no shell string injection, no hardcoded paths), convention compliance, missing tests.
- May leave inline comments but does NOT push code changes — only approves or requests changes.
- Reviewer approval is required before any phase branch is merged to `main`.

### Refactorer

**Responsibility:** Improve existing code quality without changing behavior.

- Works only after a phase is complete and merged.
- Scope is explicitly bounded in the prompt packet (e.g., "refactor `GitService.swift` only").
- Must not add new features or change public interfaces.
- Must run all existing tests before and after; tests must pass both times.

### Test/QA

**Responsibility:** Write or expand tests, run manual acceptance scripts, and surface regressions.

- Works from the acceptance criteria in `plan.md §10` for the targeted phase.
- May add test files and test helpers; must not modify production code.
- Reports pass/fail per criterion in the PR description.
- For Phase 5–6, executes the manual test scripts documented in `plan.md` Appendix.

---

## 2. Workflow Protocol

Every change follows this sequence. No step may be skipped.

```
1. CLAIM    → State the phase number and deliverable you are implementing.
              Example: "Phase 2 / GitService.createWorktree"

2. BRANCH   → Create a feature branch from main:
              git checkout main && git pull origin main
              git checkout -b feat/phase<N>/<short-description>
              Example: feat/phase2/git-service-worktree-create

3. BUILD    → Implement the deliverable per plan.md §10 for the phase.
              Reference the phase checklist (see below) on every commit.

4. TEST     → Run swift test (SpurCore) before any push.
              All tests must pass. Do not push with failing tests.

5. COMMIT   → Follow commit message format (§3.2).
              Each commit must reference phase and deliverable.

6. PUSH     → git push -u origin <branch>

7. PR       → Open PR with the PR checklist (§3.3) completed.
              Title format: [PhaseN] Short description
              Example: [Phase2] Implement GitService worktree create/remove

8. REVIEW   → A Reviewer role (separate model session or human) must approve.

9. MERGE    → Squash merge to main with the standard commit format.

10. CLOSE   → Mark todos / prompt-sequence items as complete.
```

### Phase Checklist (embed in every PR description)

```
## Phase Checklist
- [ ] plan.md section referenced: §10.Phase<N>
- [ ] All acceptance criteria from plan.md met (list each criterion with PASS/FAIL)
- [ ] No shell string injection (grep for `sh -c` returns empty in changed files)
- [ ] No hardcoded absolute paths (grep for `/Users/` or `/home/` returns empty)
- [ ] swift test passes (attach output)
- [ ] No new compiler warnings introduced
- [ ] New logic has unit/integration tests
- [ ] Reviewer role has approved
```

---

## 3. Conventions

### 3.1 Branch Naming

Feature branches (for agent development work):

```
feat/phase<N>/<short-description>
```

- `N` is the phase number (1–6).
- `short-description`: lowercase, hyphens, max 40 chars.
- Examples:
  - `feat/phase1/persistence-service`
  - `feat/phase2/git-service-worktree`
  - `feat/phase3/dev-server-streaming`

**App-managed Option branches** (created by Spur at runtime — do not use for development):

```
exp/<experimentId8>/<optionSlug>
```

These are described in `plan.md §2` and `plan.md §5.3`. Do not manually create branches in this namespace.

### 3.2 Commit Message Format

```
[PhaseN][Role] Short imperative summary (max 72 chars)

Body (optional): explain WHY, not WHAT. Reference plan.md sections.
Link to acceptance criterion if applicable.

Refs: plan.md §10.Phase<N>
```

Examples:

```
[Phase1][Builder] Add PersistenceService JSON read/write

Implements plan.md §5.11 and §10.Phase1.
Uses atomic write (write to .tmp, rename) to prevent corruption.

Refs: plan.md §10.Phase1
```

```
[Phase2][Reviewer] Request changes: missing integration test for Path B fork

git worktree add from a SHA is not tested. Acceptance criterion 3 in
plan.md §10.Phase2 explicitly requires this.

Refs: plan.md §10.Phase2
```

### 3.3 PR Checklist

Every PR must include this block in its description, with all items checked before requesting review:

```markdown
## PR Checklist

### Identity
- [ ] Phase number: PhaseN
- [ ] Role: Builder | Reviewer | Refactorer | Test/QA
- [ ] Deliverable (from plan.md §10): [exact deliverable name]

### Correctness
- [ ] All acceptance criteria in plan.md §10.PhaseN are met
- [ ] Each criterion listed with PASS/FAIL status

### Security
- [ ] No shell string construction (`sh -c "..."` or `Process` with single string arg)
- [ ] All user inputs pass through SlugSanitizer before use in paths or branch names
- [ ] No secrets or API keys in code or comments

### Quality
- [ ] `swift test` output attached or linked
- [ ] Zero new compiler warnings (`-warnings-as-errors` must still pass)
- [ ] Public interfaces have doc comments (`///`)
- [ ] No dead code left in (no `// TODO: remove` comments in production files)

### Review
- [ ] Reviewer role has read and approved (or: this IS the Reviewer's approval comment)
```

### 3.4 Code Style

Apply these rules to all Swift files under `SpurCore/` and `SpurApp/`:

**Naming:**
- Types: `UpperCamelCase`
- Functions, variables, parameters: `lowerCamelCase`
- Constants: `lowerCamelCase` (not `SCREAMING_SNAKE`)
- Protocol names: noun or noun phrase (e.g., `GitOperating`, `PersistenceProviding`)

**Structure:**
- One type per file. File name matches type name.
- Extensions in the same file unless the extension adds conformance to an external protocol, in which case a separate file named `TypeName+ProtocolName.swift` is acceptable.
- `// MARK: -` sections for logical groupings within a type.

**Spacing and length:**
- 4-space indentation. No tabs.
- Max line length: 120 chars.
- No trailing whitespace.
- One blank line between functions; two blank lines between type-level declarations.

**Immutability:**
- Prefer `let` over `var` everywhere possible.
- Prefer value types (`struct`, `enum`) over reference types (`class`) in `SpurCore`.
- `class` is acceptable in `SpurApp` ViewModels (for `ObservableObject`).

**Process safety (non-negotiable):**
- Never use `Process` with a shell executable (`/bin/sh`, `/bin/bash`, `sh`, `bash`).
- Always set `process.executableURL` to the full tool path (e.g., `/usr/bin/git`).
- Always set `process.arguments` as `[String]` array.
- Resolve tool paths via `ProcessRunner.resolvedPath(for:)` (which uses `/usr/bin/which`).

**Async:**
- Use `async/await` and `AsyncStream` for all I/O.
- No `DispatchQueue.main.async` in `SpurCore`; UI dispatch is the app layer's responsibility.
- Annotate `@MainActor` on ViewModels.

### 3.5 Logging

- Use `os.Logger` (unified logging) in production code. Logger category = type name.
- Log levels:
  - `.debug`: verbose git command arguments, raw output lines.
  - `.info`: state transitions (option started, checkpoint captured).
  - `.error`: unexpected failures with full error description.
- Never log user file contents or git commit messages (may contain secrets).
- User-visible log strings in `CommandPanelView` and `TurnListView` come from `AsyncStream<String>` passed by the service, not from `os.Logger`.

```swift
// Example
import os
private let logger = Logger(subsystem: "com.spur.app", category: "GitService")
logger.info("Creating worktree at \(worktreePath, privacy: .private)")
```

### 3.6 Error Handling

- All public service methods throw typed errors.
- Define error enums per service: `GitServiceError`, `DevServerError`, `PersistenceError`, etc.
- Each error case carries a `localizedDescription` suitable for display.
- Errors must include the raw stderr from failed processes where applicable.
- Never use `try!` or `try?` in production code; only in tests with explicit `XCTAssertNoThrow`.
- Error propagation: services throw → ViewModels catch and set `@Published var error: String?` → Views display via `.alert`.

```swift
enum GitServiceError: LocalizedError {
    case worktreeCreateFailed(stderr: String)
    case pushFailed(branch: String, stderr: String)
    case gitNotFound

    var errorDescription: String? {
        switch self {
        case .worktreeCreateFailed(let stderr):
            return "Failed to create worktree: \(stderr)"
        case .pushFailed(let branch, let stderr):
            return "Failed to push branch \(branch): \(stderr)"
        case .gitNotFound:
            return "git not found on PATH. Please install Xcode Command Line Tools."
        }
    }
}
```

---

## 4. Prompt Packet Format

When handing a task to another coding model, always use this template. This ensures the receiving model has full context without needing to read the entire codebase.

```markdown
# Prompt Packet — Spur / Phase<N> / <Deliverable Name>

## Role
<Builder | Reviewer | Refactorer | Test/QA>

## Context
- Product: Spur (macOS app, plan.md is the source of truth)
- Phase: <N> — <Phase Name>
- This packet is self-contained. Do not invent requirements not listed here.

## Source of Truth Sections
Read these sections of plan.md before writing any code:
- §2 Branch + Worktree Philosophy
- §4 Technical Choices
- §9 Data Model
- §10.Phase<N> (acceptance criteria for this phase)

## Inputs (files/modules you must read first)
- <path/to/FileA.swift> — <why it matters>
- <path/to/FileB.swift> — <why it matters>

## Task
<1–3 sentences. Exactly what to implement. No more, no less.>

## Constraints
- Do NOT modify files outside of: <list of files/directories in scope>
- Do NOT add features not listed in plan.md §10.Phase<N>
- All ProcessRunner calls must use executable + args array (no shell strings)
- Follow agents.md §3 conventions exactly

## Outputs Expected
- <New or modified file path> — <what it should contain>
- <Test file path> — <what tests must pass>

## Compile / Run Acceptance Check
Run these commands. All must exit 0:
```
cd SpurCore && swift build 2>&1 | grep -E "error:|warning:"
cd SpurCore && swift test --filter <TestSuiteName>
```
Expected: zero errors, zero warnings, all listed tests PASS.

## Acceptance Criteria (from plan.md §10.Phase<N>)
Copy the exact acceptance criteria bullet points here so the model
can check each one without re-reading plan.md.
- [ ] Criterion 1
- [ ] Criterion 2
- ...
```

---

## 5. Prompt Sequence

This section breaks the entire Spur build into narrowly scoped future prompts. Each prompt corresponds to one phase deliverable. Execute them in order; each prompt's outputs are inputs to the next.

Prompts are written in the Prompt Packet format defined in §4. They are ready to copy-paste to a coding model session.

---

### Prompt 1 — Models + Persistence Foundation

```markdown
# Prompt Packet — Spur / Phase 1 / Models + PersistenceService

## Role
Builder

## Context
- Product: Spur (macOS app, plan.md is the source of truth)
- Phase: 1 — Foundation
- Swift Package: SpurCore (no UI dependencies)

## Source of Truth Sections
Read: plan.md §9 (Data Model), §10.Phase1, §5.11

## Inputs
- plan.md §9 — defines all model structs and enums
- plan.md §5.11 — defines persistence path and schema version

## Task
Create all model structs (AppStateFile, ExperimentRecord, OptionRecord,
TurnRecord and their status enums) as Codable, Identifiable value types.
Implement PersistenceService with read(repoSlug:) and write(_:repoSlug:)
methods using atomic JSON writes to ~/.spur/state/<slug>.json.

## Constraints
- Files in scope: SpurCore/Sources/SpurCore/Models/, SpurCore/Sources/SpurCore/Services/PersistenceService.swift
- No UI code. No AppKit/SwiftUI imports anywhere in SpurCore.
- Use atomic write: write to <path>.tmp then rename to <path>.

## Outputs Expected
- SpurCore/Sources/SpurCore/Models/AppStateFile.swift
- SpurCore/Sources/SpurCore/Models/ExperimentRecord.swift
- SpurCore/Sources/SpurCore/Models/OptionRecord.swift
- SpurCore/Sources/SpurCore/Models/TurnRecord.swift
- SpurCore/Sources/SpurCore/Services/PersistenceService.swift
- SpurCore/Tests/SpurCoreTests/PersistenceServiceTests.swift

## Compile / Run Acceptance Check
```
cd SpurCore && swift build 2>&1 | grep -E "^.*error:"
cd SpurCore && swift test --filter PersistenceServiceTests
```
Expected: zero errors, all tests PASS.

## Acceptance Criteria
- [ ] JSON round-trip: create full AppStateFile, serialize, deserialize, compare equality
- [ ] Version field present and defaults to 1
- [ ] Atomic write test: simulate crash after .tmp write; original file intact
- [ ] Missing keys deserialize with defaults (no crash on partial JSON)
```

---

### Prompt 2 — SlugSanitizer + PortAllocator + ProcessRunner

```markdown
# Prompt Packet — Spur / Phase 1 / Utilities

## Role
Builder

## Context
- Phase: 1 — Foundation
- These utilities are used by every other service. Get them right.

## Source of Truth Sections
Read: plan.md §2 (branch naming regex), §5.3 (branch naming), §6 (process safety)

## Inputs
- plan.md §2 — branch naming convention and validation regex
- plan.md §6 — process safety rules

## Task
Implement three utilities:
1. SlugSanitizer: sanitize(name:) -> String (lowercase, alphanum+hyphens, max 40
   chars, strip leading/trailing hyphens, append -2/-3 on collision).
   Also: branchName(experimentId8:slug:) -> String validated against regex in plan.md §2.
2. PortAllocator: allocate() -> Int (range 3100–3199), release(port:),
   isAvailable(port:) -> Bool using bind() socket test.
3. ProcessRunner: run(executableName:arguments:workingDirectory:) async throws -> ProcessResult
   (stdout: String, stderr: String, exitCode: Int32).
   resolvedPath(for executableName:) -> String? using /usr/bin/which.
   Never use sh/bash as executable.

## Constraints
- Files in scope: SpurCore/Sources/SpurCore/Utilities/
- No shell strings in ProcessRunner under any condition.

## Outputs Expected
- SpurCore/Sources/SpurCore/Utilities/SlugSanitizer.swift
- SpurCore/Sources/SpurCore/Utilities/PortAllocator.swift
- SpurCore/Sources/SpurCore/Utilities/ProcessRunner.swift
- SpurCore/Tests/SpurCoreTests/SlugSanitizerTests.swift
- SpurCore/Tests/SpurCoreTests/PortAllocatorTests.swift

## Compile / Run Acceptance Check
```
cd SpurCore && swift build 2>&1 | grep -E "^.*error:"
cd SpurCore && swift test --filter SlugSanitizerTests
cd SpurCore && swift test --filter PortAllocatorTests
```

## Acceptance Criteria
- [ ] Slug: spaces → hyphens, special chars stripped, Unicode normalized/stripped
- [ ] Slug: max 40 chars enforced, leading/trailing hyphens removed
- [ ] Slug: collision suffix appends -2, -3, up to -99
- [ ] Branch name matches regex ^exp\/[0-9a-f]{8}\/[a-z0-9\-]{1,40}$
- [ ] PortAllocator: allocates unique ports, rejects duplicates, releases correctly
- [ ] ProcessRunner: grep for sh -c in ProcessRunner.swift returns zero matches
- [ ] ProcessRunner: runs /usr/bin/echo with args, returns correct stdout
```

---

### Prompt 3 — GitService: Worktree Create, Push, List

```markdown
# Prompt Packet — Spur / Phase 2 / GitService (worktree + push)

## Role
Builder

## Context
- Phase: 2 — Git Integration
- The branch+worktree philosophy in plan.md §2 is the core product invariant.
  Read it fully before writing a single line.

## Source of Truth Sections
Read: plan.md §2 (all of it), §5.4, §5.9, §10.Phase2

## Inputs
- SpurCore/Sources/SpurCore/Utilities/ProcessRunner.swift
- SpurCore/Sources/SpurCore/Utilities/SlugSanitizer.swift
- plan.md §2 (exact git commands to use)

## Task
Implement GitService with:
- createWorktree(repoRoot:worktreePath:branchName:from:) async throws
  where `from` is either .mainBranch(name: String) or .commit(sha: String).
  Must use `git worktree add <path> -b <branch> <startPoint>` via ProcessRunner.
- push(branchName:worktreePath:) async throws — uses git push -u origin <branch>
- removeWorktree(repoRoot:worktreePath:) async throws — git worktree remove --force
- listWorktrees(repoRoot:) async throws -> [WorktreeInfo]
- currentHEAD(worktreePath:) async throws -> String
- detectRemoteURL(repoRoot:) async throws -> String?
Write integration tests using a real temp git repo + local bare repo as origin.

## Constraints
- Files in scope: SpurCore/Sources/SpurCore/Services/GitService.swift,
  SpurCore/Tests/SpurCoreTests/GitServiceTests.swift
- All git commands via ProcessRunner. No shell strings.
- Integration tests must use a temp directory (FileManager.default.temporaryDirectory).

## Outputs Expected
- SpurCore/Sources/SpurCore/Services/GitService.swift
- SpurCore/Tests/SpurCoreTests/GitServiceTests.swift

## Compile / Run Acceptance Check
```
cd SpurCore && swift build 2>&1 | grep -E "^.*error:"
cd SpurCore && swift test --filter GitServiceTests
```

## Acceptance Criteria
- [ ] Integration test: Path A (from main) → worktree exists, branch exists, pushable to bare repo
- [ ] Integration test: Path B (from SHA) → new worktree at exact commit, verifiable via git log
- [ ] Integration test: removeWorktree → directory gone, git worktree list no longer shows it
- [ ] No sh -c usage anywhere in GitService.swift (grep must return empty)
- [ ] GitServiceError enum with worktreeCreateFailed, pushFailed, gitNotFound cases
```

---

### Prompt 4 — CheckpointService: Turn Capture, Commit Range

```markdown
# Prompt Packet — Spur / Phase 2 / CheckpointService

## Role
Builder

## Context
- Phase: 2 — Git Integration
- Checkpoint capture has two cases: external tool committed vs. did not commit.
  Both are described in plan.md §5.8.

## Source of Truth Sections
Read: plan.md §5.7, §5.8, §9 (TurnRecord), §10.Phase2

## Inputs
- SpurCore/Sources/SpurCore/Services/GitService.swift (already built)
- SpurCore/Sources/SpurCore/Models/TurnRecord.swift (already built)
- plan.md §5.8

## Task
Implement CheckpointService:
- startTurn(name:worktreePath:) async throws -> TurnRecord
  Records current HEAD as turnStartSHA.
- captureCheckpoint(turn:worktreePath:) async throws -> TurnRecord
  Case 1 (no external commits): runs git add -A then git commit -m "turn: <name>".
  Case 2 (external commits exist): reads git log <startSHA>..HEAD --format=%H.
  Detection: compare currentHEAD vs turn.startSHA.
  After either case: calls GitService.push.
  Returns updated TurnRecord with checkpointSHA and commits populated.

## Constraints
- Files in scope: SpurCore/Sources/SpurCore/Services/CheckpointService.swift,
  SpurCore/Tests/SpurCoreTests/CheckpointServiceTests.swift
- Must use GitService (not raw ProcessRunner) for git operations where possible.

## Outputs Expected
- SpurCore/Sources/SpurCore/Services/CheckpointService.swift
- SpurCore/Tests/SpurCoreTests/CheckpointServiceTests.swift

## Compile / Run Acceptance Check
```
cd SpurCore && swift test --filter CheckpointServiceTests
```

## Acceptance Criteria
- [ ] Case 1 test: no external commits → app commits → checkpointSHA populated
- [ ] Case 2 test: simulate external tool committing 3 commits → range detected → all 3 SHAs in turn.commits
- [ ] Push is called after both cases (verify via mock or bare repo)
- [ ] captureCheckpoint on a clean worktree with no changes returns a clear error (not a silent empty commit)
```

---

### Prompt 5 — DevServerService + Log Streaming

```markdown
# Prompt Packet — Spur / Phase 3 / DevServerService

## Role
Builder

## Context
- Phase: 3 — Dev Server + Preview
- Multiple Options may run concurrently. Log streams must not block the UI.

## Source of Truth Sections
Read: plan.md §5.5, §6, §10.Phase3

## Inputs
- SpurCore/Sources/SpurCore/Utilities/ProcessRunner.swift
- SpurCore/Sources/SpurCore/Utilities/PortAllocator.swift
- SpurCore/Sources/SpurCore/Models/OptionRecord.swift

## Task
Implement DevServerService:
- start(optionId:worktreePath:port:) async throws
  Spawns `npm run dev -- --port <port>` via a streaming Process (not ProcessRunner.run,
  since this is long-running). Returns immediately; logs stream asynchronously.
- stop(optionId:) async
  Terminates the process; releases port via PortAllocator.
- logStream(optionId:) -> AsyncStream<String>
  Consumers subscribe to receive log lines as they arrive.
- status(optionId:) -> OptionStatus

Internally, keep a [UUID: RunningServer] dictionary where RunningServer holds
the Process reference and an AsyncStream continuation.

## Constraints
- Files in scope: SpurCore/Sources/SpurCore/Services/DevServerService.swift
- Do not use ProcessRunner.run for the server process (it waits for exit).
  Use Process + Pipe with FileHandle.readabilityHandler for streaming.
- No UI code.

## Outputs Expected
- SpurCore/Sources/SpurCore/Services/DevServerService.swift

## Compile / Run Acceptance Check
```
cd SpurCore && swift build 2>&1 | grep -E "^.*error:"
```
(Full integration test requires npm; not required in CI — documented as manual test.)

## Acceptance Criteria
- [ ] start() spawns process; logStream emits lines without UI blocking
- [ ] stop() terminates process within 2 seconds
- [ ] Concurrent start() for two different optionIds works independently
- [ ] If npm not found: throws DevServerError.npmNotFound with clear message
- [ ] status() transitions: idle → starting → running → idle (on stop)
```

---

### Prompt 6 — PreviewWebView + OptionDetailView Layout

```markdown
# Prompt Packet — Spur / Phase 3 / PreviewWebView + OptionDetailView

## Role
Builder

## Context
- Phase: 3 — Dev Server + Preview
- UI only. No new service logic. WKWebView must load localhost without ATS errors.

## Source of Truth Sections
Read: plan.md §5.6, §4 (WKWebView choice), §3 (architecture)

## Inputs
- SpurApp/Views/ (existing skeleton)
- SpurCore/Sources/SpurCore/Services/DevServerService.swift

## Task
1. Implement PreviewWebView.swift: NSViewRepresentable wrapping WKWebView.
   WKWebViewConfiguration must disable ATS for localhost.
   Accept a `url: URL?` binding; reload when url changes.
   Show a "Server not running" placeholder when url is nil.
2. Implement OptionDetailView.swift layout:
   - Top: tab bar (OptionTabBarView, passed in).
   - Main: PreviewWebView (flex).
   - Bottom drawer: CommandPanelView placeholder + TurnListView placeholder.
   - Status badge: shows OptionStatus with color indicator.
   - Buttons: Start/Stop Server, Reload Preview, Open in Terminal.app.

## Constraints
- Files in scope: SpurApp/Views/PreviewWebView.swift,
  SpurApp/Views/OptionDetailView.swift
- No new services. Wire to DevServerService via OptionViewModel (passed as @ObservedObject).
- Info.plist must include NSAppTransportSecurity → NSAllowsLocalNetworking: true.

## Outputs Expected
- SpurApp/Views/PreviewWebView.swift
- SpurApp/Views/OptionDetailView.swift
- SpurApp/Info.plist (updated with ATS key)

## Compile / Run Acceptance Check
```
xcodebuild -scheme Spur -destination 'platform=macOS' build 2>&1 | grep -E "error:"
```

## Acceptance Criteria
- [ ] App builds for macOS 13 with zero errors
- [ ] WKWebView loads http://localhost:3100 without ATS error (manual test)
- [ ] Placeholder shown when no server running
- [ ] Status badge updates when DevServerService status changes
```

---

### Prompt 7 — CommandPanelView + TurnListView + Open in Terminal

```markdown
# Prompt Packet — Spur / Phase 4 / CommandPanelView + TurnListView

## Role
Builder

## Context
- Phase: 4 — Command Panel, Turns, Fork, PR (MVP Complete)
- Command execution MUST use ProcessRunner with explicit executable path.
  Never sh -c.

## Source of Truth Sections
Read: plan.md §5.7, §5.8, §10.Phase4

## Inputs
- SpurCore/Sources/SpurCore/Utilities/ProcessRunner.swift
- SpurCore/Sources/SpurCore/Services/CheckpointService.swift
- SpurApp/ViewModels/OptionViewModel.swift

## Task
1. CommandPanelView: text field for command input (split into executable + args on
   whitespace), Run button, streaming output log (ScrollView + Text, auto-scroll),
   Clear button, "Open in Terminal.app" button.
   "Open in Terminal.app" uses NSWorkspace to open Terminal at worktreePath:
   NSWorkspace.shared.open(worktreeURL, configuration: ...) or AppleScript open.
2. TurnListView: list of TurnRecords for the current Option.
   Each row: turn name, createdAt, capturedAt (or "In Progress"), commit count,
   "Fork from here" button (disabled if checkpointSHA is nil),
   "Capture Checkpoint" button (only on the latest in-progress turn).
3. Wire "Capture Checkpoint" to CheckpointService via OptionViewModel.
4. Wire "Fork from here" to GitService.createWorktree Path B via OptionViewModel;
   creates new OptionRecord, adds to ExperimentRecord, saves via PersistenceService.

## Constraints
- Files in scope: SpurApp/Views/CommandPanelView.swift,
  SpurApp/Views/TurnListView.swift, SpurApp/ViewModels/OptionViewModel.swift
- Command parsing: split input string on whitespace → [String]; first element is
  executableName (resolved via ProcessRunner.resolvedPath), rest are arguments.
  If executable not found: show error in log, do not run.

## Outputs Expected
- SpurApp/Views/CommandPanelView.swift
- SpurApp/Views/TurnListView.swift
- SpurApp/ViewModels/OptionViewModel.swift (updated)

## Compile / Run Acceptance Check
```
xcodebuild -scheme Spur -destination 'platform=macOS' build 2>&1 | grep -E "error:"
```

## Acceptance Criteria
- [ ] Run button executes command in worktree directory; output streams line by line
- [ ] Non-zero exit code surfaces error message in log (red text or error prefix)
- [ ] "Open in Terminal.app" opens Terminal at the correct worktreePath
- [ ] "Fork from here" creates new Option tab with correct branch from Turn's checkpointSHA
- [ ] "Capture Checkpoint" works for Case 1 and Case 2 (per plan.md §5.8)
- [ ] All state persists after app quit and relaunch
```

---

### Prompt 8 — PRService: gh CLI + Browser Fallback

```markdown
# Prompt Packet — Spur / Phase 4 / PRService

## Role
Builder

## Context
- Phase: 4 — MVP Complete
- PR creation is a hard requirement (plan.md §5.10). Must work for every Option.

## Source of Truth Sections
Read: plan.md §2 (PR creation), §5.10, §10.Phase4

## Inputs
- SpurCore/Sources/SpurCore/Utilities/ProcessRunner.swift
- SpurCore/Sources/SpurCore/Models/OptionRecord.swift
- SpurCore/Sources/SpurCore/Models/ExperimentRecord.swift

## Task
Implement PRService:
- createPR(option:experiment:repoRoot:baseBranch:) async throws -> PRResult
  Step 1: resolvedPath for "gh". If nil → fallback.
  Step 2: run `gh auth status`; if exits non-zero → fallback.
  Step 3: run `gh pr create --base <baseBranch> --head <branchName>
            --title "<optionName>" --body "Spur Option: <optionName>, Experiment: <experimentName>"`
  Parse stdout for PR URL (line starting with https://).
  On any failure: fallback.
  Fallback: construct GitHub compare URL from remoteURL + branchName;
  open via NSWorkspace.shared.open(_:). Return PRResult.openedInBrowser(url:).

PRResult: enum { ghCLI(prURL: String, prNumber: Int?), openedInBrowser(url: URL) }

## Constraints
- Files in scope: SpurCore/Sources/SpurCore/Services/PRService.swift,
  SpurApp/Views/PRBadgeView.swift
- NSWorkspace is AppKit; import it only in PRService. SpurCore may import AppKit
  since it targets macOS only.
- All gh invocations via ProcessRunner. No shell strings.

## Outputs Expected
- SpurCore/Sources/SpurCore/Services/PRService.swift
- SpurApp/Views/PRBadgeView.swift (shows PR URL badge on Option tab when prURL set)

## Compile / Run Acceptance Check
```
cd SpurCore && swift build 2>&1 | grep -E "^.*error:"
xcodebuild -scheme Spur -destination 'platform=macOS' build 2>&1 | grep -E "error:"
```

## Acceptance Criteria
- [ ] gh path not found → opens browser at correct compare URL
- [ ] gh auth status non-zero → opens browser fallback
- [ ] gh pr create succeeds → PR URL parsed and returned
- [ ] PRResult persisted to OptionRecord.prURL after success
- [ ] PRBadgeView shows "PR #N" or "PR ↗" badge on tab when prURL is set
- [ ] No shell strings (grep for sh -c in PRService.swift returns empty)
```

---

### Prompt 9 — Reviewer Pass: Phase 1–4 Security + Quality Audit

```markdown
# Prompt Packet — Spur / Phase 4 / Reviewer Audit

## Role
Reviewer

## Context
- Phases 1–4 are complete. This is a full security and quality review
  before declaring MVP done.

## Task
Review all files in SpurCore/Sources/ and SpurApp/ against the checklist below.
Do NOT write new features. Only identify issues and propose fixes.
Output a numbered list of findings with: file, line range, issue, severity (critical/major/minor), suggested fix.

## Review Checklist
1. Shell injection: any Process call using sh/bash as executable → CRITICAL
2. User input in paths: any place user-provided string reaches a file path
   without going through SlugSanitizer → CRITICAL
3. Hardcoded paths (/Users/, /home/) in production code → MAJOR
4. try! or try? in production code (non-test files) → MAJOR
5. Missing error cases: service functions that can fail but have no error thrown → MAJOR
6. Memory leaks: closures capturing self strongly in long-lived services → MAJOR
7. Missing doc comments on public interfaces → MINOR
8. Dead code (functions defined but never called) → MINOR
9. Plan.md compliance: any behavior that contradicts plan.md §2, §5, or §6 → CRITICAL

## Outputs Expected
- A findings report as a PR comment or markdown file at docs/review-phase4.md

## Acceptance Criteria
- [ ] Zero CRITICAL findings unresolved
- [ ] All MAJOR findings either fixed or explicitly accepted with rationale
```

---

### Prompt 10 — Phase 5: Onboarding, Settings, Error Recovery

```markdown
# Prompt Packet — Spur / Phase 5 / Onboarding + Settings + Error Recovery

## Role
Builder

## Context
- Phase: 5 — Polish
- This phase hardens the app for daily use. No new git features.

## Source of Truth Sections
Read: plan.md §10.Phase5

## Inputs
- All existing SpurApp/Views/ and SpurApp/ViewModels/
- SpurCore/Sources/SpurCore/Services/ (all services)

## Task
1. Onboarding sheet: on first launch (no repos stored), show sheet checking
   for git ≥ 2.30, npm, gh on PATH. Use ProcessRunner to check each.
   Show install link for any missing tool. "Continue anyway" allowed.
2. Settings window: NSWindow or SwiftUI Settings scene.
   Fields: default base branch (default "main"), worktrees root path
   (default "~/.spur/worktrees"), port range start (default 3100).
   Persist to UserDefaults.
3. Worktree refresh: "Refresh" toolbar button calls GitService.listWorktrees,
   reconciles with stored Options, marks stale (worktree path missing on disk).
4. Stale worktree recovery: if Option.status is stale, show "Re-create Worktree"
   button that re-runs createWorktree using the existing branchName (fetches
   from origin if needed).
5. Log export: "Copy All Logs" button in CommandPanelView copies full log string
   to NSPasteboard.

## Constraints
- Files in scope: SpurApp/Views/OnboardingView.swift, SpurApp/Views/SettingsView.swift,
  updates to CommandPanelView.swift, updates to GitService.swift (refresh/reconcile),
  updates to OptionViewModel.swift (stale detection).

## Outputs Expected
- SpurApp/Views/OnboardingView.swift
- SpurApp/Views/SettingsView.swift
- Updated: CommandPanelView.swift, GitService.swift, OptionViewModel.swift

## Compile / Run Acceptance Check
```
xcodebuild -scheme Spur -destination 'platform=macOS' build 2>&1 | grep -E "error:"
cd SpurCore && swift test
```

## Acceptance Criteria (from plan.md §10.Phase5)
- [ ] Onboarding correctly identifies missing tools and shows actionable message
- [ ] Missing-worktree recovery: simulate rm -rf on worktree → Refresh detects → Re-create restores
- [ ] Settings values are persisted across app restarts
- [ ] Log export copies correct text to clipboard
```

---

*End of agents.md — refer to plan.md for all product decisions.*
