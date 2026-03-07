# Spur — Engineering Plan

> **Product name:** Spur
> **Platform:** macOS 13+, native SwiftUI app, direct distribution (no App Store sandbox)
> **Status:** Pre-implementation planning
> **Source of truth for all coding agents:** this file + `agents.md`

---

## Table of Contents

1. [Product Overview](#1-product-overview)
2. [Branch + Worktree Philosophy](#2-branch--worktree-philosophy)
3. [Architecture Overview](#3-architecture-overview)
4. [Technical Choices & Justifications](#4-technical-choices--justifications)
5. [Functional Requirements](#5-functional-requirements)
6. [Non-Functional Requirements](#6-non-functional-requirements)
7. [Non-Requirements](#7-non-requirements)
8. [Repository Scaffold](#8-repository-scaffold)
9. [Data Model](#9-data-model)
10. [Phases of Build](#10-phases-of-build)
11. [Appendix: Later](#11-appendix-later)

---

## 1. Product Overview

Spur is a native macOS app that accelerates web prototype exploration by giving designers and developers a structured "canvas" for divergent ideas. Each idea lives on its own git branch and git worktree, runs its own Next.js dev server, and is previewed inline. Exploration state is organized into **Experiments** (sessions/canvases) and **Options** (ideas within a session, shown as tabs).

The defining capability is **deterministic forking**: any prior checkpoint commit (a "Turn") can be branched from to produce a new Option whose code state is exactly reproducible. This is analogous to a Dogma-style design canvas—duplicate, diverge, compare—but adapted for live web prototype code.

### What Spur is NOT

The "chat" surface is **not** an in-app LLM. Spur provides a command/terminal panel where users run any **external** agentic coding tool they choose (Claude Code, Codex CLI, Aider, etc.). Spur's job is to manage git state, dev servers, previews, and checkpoints around that external tooling.

### Core Loop

```
Select Repo
    └── Create Experiment
            └── Create Option (branch + worktree from main)
                    ├── Open in Terminal / run external tool
                    ├── Capture Checkpoint (Turn N) → commit → push
                    ├── View preview (WKWebView ← localhost:<port>)
                    ├── Fork from Turn N → new Option (branch+worktree at commit)
                    └── Create PR from Option branch → GitHub
```

**Rule A (invariant):** Every Option branch is pushed to `origin` on creation and pushed again after every checkpoint commit. Branches must always be remote-tracking.

---

## 2. Branch + Worktree Philosophy

This section is **central to every implementation decision** in Spur. All coding agents must internalize and apply this model consistently.

### Vocabulary

| Term | Meaning |
|---|---|
| **Experiment** | A named exploration session; groups related Options. |
| **Option** | One divergent idea: a git branch + a git worktree directory + a dev server process. |
| **Turn / Checkpoint** | A named snapshot of work; linked to one or more git commit hashes. |
| **Base branch** | The repo's default branch (e.g., `main`). New Options start here unless forking from a Turn. |
| **Worktree** | A lightweight additional working directory (`git worktree add`). Each Option gets exactly one worktree. |
| **Branch** | The durable identity: can be pushed, diffed, and PR'd. The worktree is ephemeral; the branch is not. |

### Philosophy Statement

> **The worktree is a lightweight checkout; the branch is the durable identity.**

A git worktree is a secondary working directory linked to a single repository. Creating a worktree does not duplicate the `.git` folder; it is cheap (seconds, disk cost ≈ size of working tree only). The branch name is what matters for pushes, PRs, and reproducibility. You can delete a worktree and re-attach it to the branch later without losing history.

### Path A — Branch from Main (default for new Options)

Used when: creating a fresh Option within an Experiment, diverging from the current tip of the base branch.

```bash
# Variables
REPO_ROOT=~/projects/my-next-app
WORKTREES_DIR=~/.spur/worktrees          # app-managed directory, outside repo
BRANCH=exp/abc123/fast-nav
SLUG=fast-nav

# 1. Create the branch at HEAD of main, plus worktree, in one command
git -C "$REPO_ROOT" worktree add \
    "$WORKTREES_DIR/$SLUG" \
    -b "$BRANCH" \
    main

# 2. Push branch immediately (Rule A)
git -C "$WORKTREES_DIR/$SLUG" push -u origin "$BRANCH"
```

Result: `~/.spur/worktrees/fast-nav/` is a full working directory at the tip of `main`, on branch `exp/abc123/fast-nav`, and the branch exists on `origin`.

### Path B — Branch + Worktree from Commit (forking from a Turn/Checkpoint)

Used when: the user selects Turn N of an existing Option and clicks "Fork from here."

```bash
# Variables
CHECKPOINT_SHA=a1b2c3d4          # the commit hash stored on the Turn
FORK_BRANCH=exp/abc123/fast-nav-v2
FORK_SLUG=fast-nav-v2

# 1. Create branch at the exact checkpoint commit, plus worktree
git -C "$REPO_ROOT" worktree add \
    "$WORKTREES_DIR/$FORK_SLUG" \
    -b "$FORK_BRANCH" \
    "$CHECKPOINT_SHA"

# 2. Push immediately (Rule A)
git -C "$WORKTREES_DIR/$FORK_SLUG" push -u origin "$FORK_BRANCH"
```

Result: `~/.spur/worktrees/fast-nav-v2/` is at exactly `a1b2c3d4`, diverging deterministically from that point. No matter when this fork is created, the state is always identical to the state at checkpoint time.

### Worktree Removal

When an Option is removed locally (MVP: no remote deletion):

```bash
# Stop dev server first (app's responsibility)
# Then remove worktree safely
git -C "$REPO_ROOT" worktree remove "$WORKTREES_DIR/$SLUG" --force
# Branch is preserved on origin; the Option can be re-attached later
```

### Branch Naming Convention

```
exp/<experimentId>/<optionSlug>
```

- `experimentId`: 8-char hex derived from experiment UUID (e.g., `abc12345`)
- `optionSlug`: lowercase, alphanumeric + hyphens, max 40 chars, derived from Option name
- Full example: `exp/abc12345/fast-navigation`
- Validation regex: `^exp\/[0-9a-f]{8}\/[a-z0-9\-]{1,40}$`

Slugs and branch names must be sanitized before use: strip special chars, lowercase, collapse spaces to hyphens. Never interpolate user input directly into shell strings.

### PR Creation

Every Option branch is PR-ready at all times (Rule A guarantees it is on `origin`). Creating a PR:

- **Preferred path:** `gh pr create --base main --head <branch> --title "<option name>" --body "..."` executed as a Process (no shell string interpolation).
- **Fallback path:** Open `https://github.com/<owner>/<repo>/compare/<branch>` in the default browser via `NSWorkspace.shared.open(_:)`.
- Persist the returned PR URL (or PR number) on the Option record.

---

## 3. Architecture Overview

```
Spur.app
├── SpurCore  (Swift package, no UI)
│   ├── Models/          (pure value types: Repo, Experiment, Option, Turn, etc.)
│   ├── Services/
│   │   ├── GitService          (worktree create/remove/list, commit, push)
│   │   ├── DevServerService    (Process management, port allocation, log streaming)
│   │   ├── CheckpointService   (Turn capture, commit range detection)
│   │   ├── PRService           (gh CLI or browser fallback)
│   │   └── PersistenceService  (JSON encode/decode, file I/O)
│   └── Utilities/
│       ├── ProcessRunner       (safe Process + Pipe, never shell strings)
│       ├── SlugSanitizer
│       └── PortAllocator
└── SpurApp  (SwiftUI target)
    ├── App/
    │   ├── SpurApp.swift
    │   └── AppState.swift      (ObservableObject root)
    ├── Views/
    │   ├── RepoSelectorView
    │   ├── ExperimentListView
    │   ├── OptionTabBarView
    │   ├── OptionDetailView    (preview + command panel + turns list)
    │   ├── PreviewWebView      (WKWebView via NSViewRepresentable)
    │   ├── CommandPanelView    (Phase 1 command runner)
    │   └── TurnListView
    └── ViewModels/
        ├── ExperimentViewModel
        └── OptionViewModel
```

Data flows unidirectionally: Views bind to ViewModels → ViewModels call SpurCore Services → Services mutate Models → PersistenceService serializes to disk.

---

## 4. Technical Choices & Justifications

| Concern | Choice | Rationale |
|---|---|---|
| UI framework | SwiftUI + AppKit bridges | Native, modern, good for tabs/split views; AppKit bridges for WKWebView and PTY (Phase 2). |
| Web preview | WKWebView via `NSViewRepresentable` | Standard macOS embedded browser; loads localhost without sandboxing issues. |
| Process execution | `Foundation.Process` + `Pipe` | No shell string injection risk; streaming stdout/stderr; cancellable. |
| Persistence | **JSON files** (custom, not SwiftData) | Simpler, portable, human-readable, no Core Data migration headaches for MVP. One JSON file per repo under `~/.spur/state/`. |
| Terminal Phase 1 | Command Runner panel + "Open in Terminal.app" | Lowest complexity; zero dependency on PTY libraries. |
| Terminal Phase 2 | PTY-backed embedded terminal (planned) | `posix_spawn` or `openpty`; deferred to Phase 5+. |
| Git operations | Shell out to `git` CLI via ProcessRunner | Reliable, consistent with user's installed git; easier to test. Do NOT use libgit2 for MVP. |
| GitHub integration | `gh` CLI (`gh pr create`) | Auth handled by user's existing `gh` installation; no OAuth tokens in app. |
| Distribution | Direct (no App Store) | Avoids sandbox restrictions on `git`, `npm`, `gh`, process spawning. |

---

## 5. Functional Requirements

### 5.1 Repo Selection
- User selects an existing local git repo (expected: Next.js app with `package.json`).
- App detects `origin` remote URL (for PR link construction).
- App stores the repo path in persisted state.
- Validation: repo must be a valid git repo (`git rev-parse --git-dir`).

### 5.2 Experiments
- An Experiment is a named grouping of Options (a "canvas exploration session").
- CRUD: create, rename, archive (no hard delete for MVP; archiving hides from default view).
- Persisted with: `id`, `name`, `createdAt`, `repoPath`, `status` (active/archived).

### 5.3 Options
- An Option represents one divergent idea within an Experiment.
- Displayed as tabs within the Experiment view for fast side-by-side comparison.
- Each Option has:
  - `id` (UUID)
  - `name` (display name)
  - `slug` (sanitized, URL/branch-safe)
  - `experimentId`
  - `branchName` (`exp/<experimentId8>/<slug>`)
  - `worktreePath` (absolute path in `~/.spur/worktrees/<experimentId8>/<slug>`)
  - `port` (allocated dev server port)
  - `status` (idle / running / error)
  - `turns` ([Turn])
  - `prURL` (optional String)
  - `prNumber` (optional Int)
  - `createdAt`
  - `originCommit` (SHA of the branch point — either tip of main or a Turn's commit)

### 5.4 Branch + Worktree Lifecycle
- **Create (Path A):** branch + worktree from `main` HEAD. Push. (See §2)
- **Create (Path B):** branch + worktree from Turn commit hash. Push. (See §2)
- **Remove locally:** stop server → `git worktree remove` → update persisted state. No remote deletion.
- **Refresh:** `git worktree list --porcelain` → reconcile with stored Options; mark stale worktrees.

### 5.5 Dev Server
- Start: `npm run dev -- --port <port>` in the worktree directory via `Process`.
- Stop: terminate Process; release port from allocator.
- Log streaming: Pipe stdout + stderr into an AsyncStream; ViewModels subscribe.
- Port allocation: start at 3100, increment per active option, avoid conflicts.
- Multiple Options may run concurrently.

### 5.6 Preview
- `WKWebView` (via `NSViewRepresentable`) loaded with `http://localhost:<port>`.
- Reload button.
- WKWebView configuration: disable App Transport Security restriction for localhost.
- Dev server status indicator (starting / running / stopped / error).

### 5.7 Command Runner Panel (Phase 1)
- A text field + Run button that executes arbitrary commands in the Option's worktree.
- Output is streamed to a scrollable log view.
- An "Open in Terminal.app" button that opens `terminal://` or uses `NSWorkspace` to open Terminal at the worktree path.
- Commands are executed as `[executable, ...args]` — never via `sh -c "..."`.

### 5.8 Turns / Checkpoints
- A Turn is a named unit of work. User creates it manually ("start turn", names it).
- **Capture Checkpoint:**
  - Case 1 — External tool did NOT commit: app runs `git add -A && git commit -m "turn: <name>"` in the worktree.
  - Case 2 — External tool DID commit: app reads `git log <turnStartSHA>..HEAD --format=%H` to get the commit range; records the range's HEAD as the Turn's checkpoint SHA.
  - After checkpoint: push branch (Rule A).
- Turn record: `id`, `name`, `startSHA`, `checkpointSHA`, `commits` ([String]), `createdAt`, `optionId`.

### 5.9 Fork from Checkpoint
- User selects a Turn → "Fork from here" → enter new Option name.
- App executes Path B (§2): `git worktree add ... -b <newBranch> <checkpointSHA>`.
- Push immediately (Rule A).
- New Option appears as a new tab in the Experiment.

### 5.10 PR Creation
- User clicks "Create PR" on an Option tab.
- App checks: branch exists on `origin` (it always should per Rule A).
- **Preferred:** run `gh pr create --base main --head <branch> --title "<name>" --body "Spur Option: <option name>, Experiment: <experiment name>"` via ProcessRunner.
- **Fallback:** if `gh` not found or returns error, open GitHub compare URL in browser.
- Persist `prURL` on the Option; show badge on tab.

### 5.11 Persistence
- Storage path: `~/.spur/state/<repoSlug>.json`
- One JSON file per linked repo.
- Schema: `{ version: Int, repo: RepoRecord, experiments: [ExperimentRecord] }` where experiments nest options which nest turns.
- Write on every mutation (no in-memory-only state except transient process handles).
- Migration: version field; handle missing keys gracefully (provide defaults).

---

## 6. Non-Functional Requirements

- **macOS 13+** minimum deployment target.
- **No in-app LLM inference.** The app never calls an AI API.
- **No App Store sandbox.** Direct distribution only.
- **Process safety:** Never construct shell command strings. Always use `Process` with explicit `executableURL` and `arguments` array. Sanitize all user-provided slugs before use in paths or branch names.
- **Streaming logs:** `AsyncStream<String>` pattern for all process output. UI must not block.
- **Error handling:** All git and npm operations surface errors to the UI with the raw stderr output visible. No silent failures.
- **Worktrees dir isolation:** All worktrees live under `~/.spur/worktrees/`, never inside the original repo root.

---

## 7. Non-Requirements

The following are explicitly **out of scope** for all build phases:

- No custom agent harness (system prompts, tool calling, model integrations) inside the app.
- No collaborative web gallery or shared experiment URLs.
- No merge automation (e.g., auto-closing sibling Options when one Option's PR merges) — see Appendix for future consideration.
- No cross-platform (iOS, iPadOS, web) support.
- No in-app LLM chat or AI inference of any kind.

---

## 8. Repository Scaffold

```
spur/
├── plan.md                          ← this file
├── agents.md                        ← multi-agent collaboration guide
├── .gitignore
├── README.md
│
├── Spur.xcodeproj/
│   └── project.pbxproj
│
├── SpurCore/                        ← Swift package (no UI dependencies)
│   ├── Package.swift
│   ├── Sources/
│   │   └── SpurCore/
│   │       ├── Models/
│   │       │   ├── RepoRecord.swift
│   │       │   ├── ExperimentRecord.swift
│   │       │   ├── OptionRecord.swift
│   │       │   ├── TurnRecord.swift
│   │       │   └── AppState.swift       ← top-level serializable state
│   │       ├── Services/
│   │       │   ├── GitService.swift
│   │       │   ├── DevServerService.swift
│   │       │   ├── CheckpointService.swift
│   │       │   ├── PRService.swift
│   │       │   └── PersistenceService.swift
│   │       └── Utilities/
│   │           ├── ProcessRunner.swift
│   │           ├── SlugSanitizer.swift
│   │           └── PortAllocator.swift
│   └── Tests/
│       └── SpurCoreTests/
│           ├── GitServiceTests.swift
│           ├── SlugSanitizerTests.swift
│           ├── PortAllocatorTests.swift
│           └── PersistenceServiceTests.swift
│
└── SpurApp/                         ← SwiftUI app target
    ├── App/
    │   ├── SpurApp.swift
    │   └── RootViewModel.swift
    ├── Views/
    │   ├── RepoSelectorView.swift
    │   ├── ExperimentListView.swift
    │   ├── OptionTabBarView.swift
    │   ├── OptionDetailView.swift
    │   ├── PreviewWebView.swift        ← WKWebView NSViewRepresentable
    │   ├── CommandPanelView.swift
    │   ├── TurnListView.swift
    │   └── PRBadgeView.swift
    └── ViewModels/
        ├── ExperimentViewModel.swift
        └── OptionViewModel.swift
```

**Worktrees directory (runtime, not in repo):**

```
~/.spur/
├── state/
│   └── <repoSlug>.json              ← persisted state per repo
└── worktrees/
    └── <experimentId8>/
        └── <optionSlug>/            ← git worktree checkout
```

---

## 9. Data Model

All types are `Codable`, `Identifiable`, value types (structs) unless noted.

```
AppStateFile
  version: Int                       // schema version, currently 1
  repoPath: String
  remoteURL: String?                 // detected from git remote get-url origin
  experiments: [ExperimentRecord]

ExperimentRecord
  id: UUID
  name: String
  createdAt: Date
  status: ExperimentStatus           // active | archived
  options: [OptionRecord]

OptionRecord
  id: UUID
  experimentId: UUID
  name: String
  slug: String                       // sanitized
  branchName: String                 // exp/<expId8>/<slug>
  worktreePath: String               // absolute path
  port: Int
  status: OptionStatus               // idle | starting | running | error
  originCommit: String               // SHA of branch point (tip of main or Turn SHA)
  turns: [TurnRecord]
  prURL: String?
  prNumber: Int?
  createdAt: Date

TurnRecord
  id: UUID
  optionId: UUID
  name: String
  startSHA: String                   // HEAD at turn start
  checkpointSHA: String?             // HEAD after checkpoint capture
  commits: [String]                  // ordered commit SHAs in this turn
  createdAt: Date
  capturedAt: Date?
```

Enums:

```
ExperimentStatus: String, Codable   // "active" | "archived"
OptionStatus: String, Codable       // "idle" | "starting" | "running" | "error"
```

---

## 10. Phases of Build

Each phase is a discrete, shippable increment. Phases 1–4 constitute the MVP milestone. Phases 5–6 are planned extensions.

---

### Phase 1 — Foundation: Repo + Persistence + Models

**Goal:** Establish the project structure, data models, persistence layer, and the Xcode workspace. No UI, no git operations yet.

**Deliverables:**
- `SpurCore` Swift package with all `Models/` structs (Codable, Identifiable).
- `PersistenceService`: read/write `~/.spur/state/<slug>.json`; handle version migration.
- `SlugSanitizer` utility: deterministic, tested sanitization of names → branch-safe slugs.
- `PortAllocator` utility: allocate/release ports from a range (3100–3199).
- `ProcessRunner` utility: safe Process + Pipe wrapper; no shell string injection.
- `SpurCore` unit tests for all utilities and persistence.
- `Spur.xcodeproj` and `SpurApp` skeleton (builds, no meaningful UI).

**Acceptance Criteria:**
- `swift test` in `SpurCore/` passes with ≥ 90% coverage on utilities.
- JSON round-trip test: create full `AppStateFile`, serialize, deserialize, compare.
- Slug sanitizer correctly handles: spaces, special chars, Unicode, max length, empty string, collision suffix.
- Port allocator correctly allocates, rejects duplicates, and releases.
- Xcode project builds for macOS 13 with zero warnings (treat warnings as errors).

**Key Risks / Mitigations:**
- Risk: SwiftData temptation creeping in. Mitigation: `PersistenceService` is the only persistence abstraction; no other file touches disk.
- Risk: Model schema churn affecting tests. Mitigation: freeze schema before writing tests; use `version` field from day one.

**Best suited role:** Builder (primary), Reviewer (schema sign-off before phase closes).

---

### Phase 2 — Git Integration: Worktrees, Branches, Commits, Push

**Goal:** Implement all git operations needed to create, manage, and push Option branches and worktrees.

**Deliverables:**
- `GitService`:
  - `createWorktree(at:branch:from:)` — Path A (from main) and Path B (from SHA).
  - `removeWorktree(at:repoRoot:)`.
  - `listWorktrees(repoRoot:)` → reconcile with stored Options.
  - `push(branch:worktreePath:)` — with `-u origin <branch>`.
  - `currentHEAD(worktreePath:)` → String (SHA).
  - `commitRange(from:to:worktreePath:)` → [String].
  - `commitAll(message:worktreePath:)` — for checkpoint Case 1.
  - `detectRemoteURL(repoRoot:)` → String?.
- `CheckpointService`: orchestrates Turn capture (both cases), then calls `GitService.push`.
- Integration tests using a real temporary git repo created in a temp directory.
- `PRService`: skeleton only (full implementation Phase 4).

**Acceptance Criteria:**
- Integration test: create temp git repo, run Path A → worktree exists, branch exists, can push to a bare repo.
- Integration test: create Turn, capture checkpoint (Case 1 and Case 2), verify correct commit SHA stored.
- Integration test: Path B fork from a checkpoint SHA → new worktree at that exact commit.
- `git worktree list` run against the temp repo reflects all created worktrees.
- All `ProcessRunner` calls use `[String]` args arrays — zero `sh -c` usage; grep tests for `sh -c` must return empty.

**Key Risks / Mitigations:**
- Risk: User's git version differences. Mitigation: require git ≥ 2.30; document in README; check at launch.
- Risk: Push failing in tests (no network). Mitigation: use a local bare repo as `origin` in all integration tests.
- Risk: Worktree path conflicts. Mitigation: `SlugSanitizer` appends collision suffix (e.g., `-2`).

**Best suited role:** Builder (primary), Integrator (for integration test harness setup).

---

### Phase 3 — Dev Server + Preview + Log Streaming

**Goal:** Start/stop npm dev servers per Option, stream logs, and show the preview in a WKWebView.

**Deliverables:**
- `DevServerService`:
  - `start(option:repoRoot:)` → allocates port, spawns `npm run dev -- --port <port>`, streams logs.
  - `stop(optionId:)` → terminates process, releases port.
  - `logStream(optionId:)` → `AsyncStream<String>`.
  - `status(optionId:)` → `OptionStatus`.
- `PreviewWebView.swift`: `NSViewRepresentable` wrapping `WKWebView`; loads `http://localhost:<port>`; WKWebViewConfiguration with ATS localhost exception.
- `OptionDetailView` layout: tab bar top, preview pane, log pane (collapsible), Turn list sidebar.
- Reload button; server start/stop toggle; status badge.
- `ExperimentListView` and `OptionTabBarView` — tab switching is instant (no server restart on tab switch).

**Acceptance Criteria:**
- Manual test: open a Next.js repo, create Option, start server, preview loads in WKWebView.
- Manual test: switch between two running Options in tabs — previews update independently.
- Log streaming: 100+ lines from `npm` appear in the log view without UI freeze (async stream on background queue).
- Memory: no retain cycles between `DevServerService` and `OptionViewModel` (Instruments leak check).
- App does not crash if `npm` is not installed; surfaces clear error in log view.

**Key Risks / Mitigations:**
- Risk: WKWebView refusing localhost. Mitigation: `NSAppTransportSecurity` key in `Info.plist` allowing arbitrary loads for localhost.
- Risk: Port conflicts with user's existing processes. Mitigation: `PortAllocator` checks `SO_REUSEADDR` availability via `bind()` test before assigning.
- Risk: npm dev output format varies by Next.js version. Mitigation: treat all output as raw text; no parsing beyond line splitting.

**Best suited role:** Builder (server + streaming), Reviewer (WKWebView sandboxing review).

---

### Phase 4 — Command Panel, Turns, Fork, PR Creation (MVP Complete)

**Goal:** Complete the core interaction loop: command runner, checkpoint capture, fork from checkpoint, and PR creation. This phase makes Spur a shippable MVP.

**Deliverables:**
- `CommandPanelView`: text input + Run button; output log; "Open in Terminal.app" button using `NSWorkspace`.
- Command execution via `ProcessRunner` in the option's worktree directory; output streamed to log.
- `TurnListView`: create Turn, display turns with SHA and commit count; "Fork from here" button per Turn.
- "Capture Checkpoint" flow:
  - Detects if external tool committed (compares HEAD to `turnStartSHA`).
  - Either runs `git add -A && git commit` (two sequential `Process` calls) or reads commit range.
  - Updates `TurnRecord.checkpointSHA` and `commits`.
  - Pushes branch (Rule A).
- "Fork from here" flow: calls `GitService.createWorktree` Path B; creates new `OptionRecord`; pushes; adds tab to Experiment.
- `PRService` full implementation:
  - Try `gh pr create` via ProcessRunner; capture stdout for PR URL.
  - On failure or `gh` not found: open GitHub compare URL via `NSWorkspace`.
  - Persist `prURL` + `prNumber` on `OptionRecord`; show PR badge on tab.
- End-to-end manual test script documented in `plan.md` Appendix.

**Acceptance Criteria:**
- E2E flow: select repo → create experiment → create option (Path A) → run external command → capture checkpoint → fork from checkpoint (Path B) → create PR → PR URL persisted and displayed.
- PR creation: `gh pr create` succeeds in test environment with a real GitHub repo; PR URL stored.
- PR fallback: with `gh` not on PATH, browser opens to correct GitHub compare URL.
- Command Runner: a command with exit code non-zero surfaces the error in log (does not silently succeed).
- "Open in Terminal.app" opens Terminal at the correct worktree path.
- All persisted state survives an app quit + relaunch cycle.

**Key Risks / Mitigations:**
- Risk: `gh` auth state unknown. Mitigation: `PRService` runs `gh auth status` first; surfaces clear error if not logged in, then falls back to browser.
- Risk: Checkpoint capture races with external tool still writing files. Mitigation: UI presents a "Pause external tool, then capture" warning; no automatic timing logic.
- Risk: Branch name collision on fork. Mitigation: `SlugSanitizer` appends `-2`, `-3`, etc.; check via `git branch --list`.

**Best suited role:** Builder (command runner, checkpoint logic), Integrator (E2E wiring), Reviewer (PR service auth edge cases).

---

### Phase 5 — Polish, Error Recovery, Settings

**Goal:** Harden the app for real-world daily use: robust error recovery, user preferences, onboarding, and accessibility.

**Deliverables:**
- Settings window: default base branch name; worktrees root path; port range.
- Onboarding: first-launch sheet checking for `git`, `npm`, `gh` on PATH; links to install if missing.
- Error recovery: if worktree directory missing (deleted externally), offer "Re-create worktree" action.
- Worktree refresh: manual "Refresh" button + auto-refresh on app foreground.
- Experiment archiving UI.
- Log export: "Copy All Logs" button per Option.
- Keyboard shortcuts: `Cmd+T` new option, `Cmd+]` / `Cmd+[` next/prev tab, `Cmd+R` reload preview.
- Accessibility: VoiceOver labels on all interactive elements.

**Acceptance Criteria:**
- Onboarding check correctly identifies missing tools and shows actionable message.
- Deleted-worktree recovery: simulate external `rm -rf` of worktree → app detects on refresh → "Re-create" restores it from branch.
- All keyboard shortcuts functional.
- VoiceOver can navigate through Experiment list and Option tabs.

**Key Risks / Mitigations:**
- Risk: Over-engineering settings. Mitigation: only expose settings that are actually variable for a real user; keep panel minimal.
- Risk: Re-create worktree fails if branch has diverged. Mitigation: re-create always uses branch HEAD (not originCommit), user sees a warning if branch tip differs from last known SHA.

**Best suited role:** Refactorer (error handling audit), Builder (settings + onboarding), Test/QA (keyboard + accessibility).

---

### Phase 6 — PTY Terminal (Embedded) + Advanced Comparisons

**Goal:** Embed a real terminal emulator within the app and add side-by-side Option comparison.

**Deliverables:**
- PTY-backed terminal panel: `openpty` + `posix_spawn`; render output using a simple VT100 parser or embed an existing Swift/ObjC terminal view.
- Side-by-side preview mode: split view showing two Options' WKWebViews simultaneously.
- Option diffing: "Compare branches" button runs `git diff <branchA>..<branchB>` and shows output in a text pane.

**Acceptance Criteria:**
- Terminal: interactive tools (vim, zsh) work correctly in the embedded PTY.
- Side-by-side: two previews load simultaneously with independent scroll state.
- Diff: output renders correctly for repos with 100+ changed lines.

**Key Risks / Mitigations:**
- Risk: PTY implementation complexity. Mitigation: evaluate `SwiftTerm` (open source Swift PTY + terminal library) as a dependency before writing custom code.
- Risk: WKWebView side-by-side memory pressure. Mitigation: cap concurrent WKWebViews; offer "pause" for non-focused pane.

**Best suited role:** Builder (PTY integration), Reviewer (security review of PTY escape sequences + process spawning).

---

## 11. Appendix: Later

The following items are acknowledged as valuable but explicitly deferred beyond Phase 6:

- **Merge automation:** When an Option's PR is merged on GitHub, automatically archive sibling Options within the same Experiment. Requires a GitHub webhook or polling loop.
- **Experiment sharing:** Export an Experiment as a bundle (JSON + branch refs) that another user can import.
- **Multi-repo support:** Simultaneously manage Options across multiple repos in one Experiment.
- **CI/CD status badges:** Show GitHub Actions run status per Option branch inside the app.
- **Selective commit staging:** Replace `git add -A` with an interactive staging view within the app.
- **App Store distribution:** Would require sandboxing audit; Process spawning of arbitrary CLIs may require Hardened Runtime entitlements review.
