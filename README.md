# Spur
 
A native macOS app for exploring multiple web prototype ideas in parallel — each in its own git branch, worktree, and live dev server.
 
## What it does
 
Most design exploration happens serially: try one idea, abandon it, try another. Spur makes it parallel. You create **Experiments** (a design question) and **Options** (divergent answers), each backed by an isolated git branch and worktree. Every Option gets its own dev server and live preview inside the app. When something looks promising, you capture a **Checkpoint**, fork from it in a new direction, and compare the results side by side.
 
The result: you can have three different component designs running simultaneously, each with their own code changes, without ever touching `git checkout`.
 
## Core loop
 
1. **Open a repo** — point Spur at any local git repo.
2. **New Experiment** — name the design question you're exploring.
3. **New Option** — Spur creates a git branch + worktree and starts a dev server on a dedicated port.
4. **Run tools** — use the built-in command runner or open a Terminal window at the worktree to run Claude Code, Aider, Codex, or any other tool.
5. **Capture a Checkpoint** — commits any dirty changes, records the commit range as a Turn, and pushes the branch.
6. **Fork from a Checkpoint** — branch from the exact commit of any past Turn to explore a different direction from that state.
7. **Create a PR** — open a pull request from any Option via `gh` or your browser.
 
## Requirements
 
- macOS 13 Ventura or later
- Xcode 15+ (to build)
- A local git repository with a remote named `origin`
- A dev server start command (defaults to `npm run dev`)
- `gh` CLI (optional — needed for in-app PR creation; falls back to browser)
 
## Building
 
```sh
git clone https://github.com/thorn14/spur
open Spur.xcodeproj
```
 
Build and run with Cmd-R, or from the command line:
 
```sh
xcodebuild -scheme Spur -destination 'platform=macOS' build
```
 
## Running tests
 
```sh
xcodebuild -scheme Spur -destination 'platform=macOS' test
```
 
## How it works
 
| Concept | What it is |
|---------|-----------|
| **Experiment** | A named design exploration session. Groups a set of Options. |
| **Option** | One divergent idea. Owns a git branch, a worktree, a dev server, and a list of Turns. |
| **Turn** | A unit of work. Records the git commit range produced during a session with an external tool. |
| **Checkpoint** | Ends a Turn by committing any dirty changes, snapshotting the commit hash, and pushing the branch. |
| **Fork** | Creates a new Option branched from the exact commit of any past Checkpoint. |
 
State is persisted to `~/.spur/<repo-id>.json`. Worktrees are created as siblings of your repo directory under a `spur-worktrees/` folder.
 
## Keyboard shortcuts
 
| Action | Shortcut |
|--------|----------|
| New Experiment | Cmd-Shift-N |
| New Option | Cmd-N |
| Start / Stop dev server | Cmd-R / Cmd-. |
| Open in Terminal | Cmd-T |
