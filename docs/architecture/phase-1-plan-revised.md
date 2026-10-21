# Phase 1 plan (revised)

**Status: plan only. Not approved. Do not implement it.**

Phase 0 is accepted as an audit. The implementation architecture is not
accepted. This file replaces the Phase 1 sequence that assumed an in-process
Swift package and a new SQLite file. That assumption is withdrawn in
[adr-0001-orchestration-backend.md](adr-0001-orchestration-backend.md).

Nothing in this plan authorizes a commit that changes `Sources/`, `CLI/`,
packages, workflows, or AgentFlow Studio.

## Stop rule

Phase 1 starts only after both of these are true:

1. Studio has been read at `35a0d1af631a53958883e61c1b98ab072195b11c` or a
   later recorded SHA, and ADR 0001 has been updated from **withheld** to a
   real selection.
2. [target-architecture.md](target-architecture.md) is marked approved by
   the user.

Until then, the only unfinished audit work is the Studio checklist below.
That checklist is still Phase 0. It is not Phase 1.

## Studio checklist (blocked on repository access)

The clone failed. Commands and exit codes are in
`reports/phase-0/baseline-results.json`. Do not invent paths. When a
checkout exists, record the SHA, then verify each claim with a path or write
"not found":

| Claim | What to open |
| --- | --- |
| pnpm/turbo monorepo | Root `package.json`, `pnpm-workspace.yaml`, `turbo.json` |
| React UI | App entry and the Kanban, Gantt, React Flow, Tiptap, and dashboard mounts, if they exist |
| TypeScript/Node backend | The process entry that is not the Electron main |
| Electron packaging | `ipcMain`, `ipcRenderer`, preload, `app.*`, `BrowserWindow`, `app.getPath` |
| Native ABI | `better-sqlite3` and any other addon built for Electron |
| Workflow execution | The function that runs a step |
| Persistence | The database file, schema, and migrations. Decide whether a second project database is impractical, with the concrete reason |
| Claude Code and Codex adapters | The modules that spawn or speak to each CLI |
| Agent teams | The type that groups agents, or "not found" |
| Git worktrees | The call that creates a worktree, or "not found" |
| Approval gates | Distinguish a blocking provider hook from a harness wait. See the approval section in [integration-points.md](integration-points.md#approval-model) |
| Project management | The project record and its id |
| MCP | The client or server setup, or "not found" |
| License | The `LICENSE` file, quoted by SPDX identifier only after it is read |

Then run, in that checkout, and record real exit codes:

- `pnpm install`
- the repo's typecheck script
- the repo's test script

Do not modify that repo and do not push to it.

## After a decision, the only cmux edits

Whichever option ADR 0001 selects, cmux changes stay inside the five
boundaries below. Workflow rules, React screens, and the project store live
in isolated packages (a Swift bridge package, Studio's existing packages, or
both). They do not move into `Workspace.swift` or `CLI/cmux.swift`.

Diff sizes are estimates from the call sites at
`72a39c338ef6e4d37e9ab29892f6561df1527781`, not measured patches. Conflict
counts are `git rev-list --count upstream/main --since=2026-09-21`.

### 1. Project identity and navigation

cmux workspaces stay layout. The project id lives in the store the ADR
selects. The bridge keeps a side table from workspace UUID to project id.
That table is not a new field on `Workspace`.

Native touch when a pane must open on a project:

| Site | Estimate | 30-day commits | Risk |
| --- | --- | --- | --- |
| `PanelType` case and decoder arm, `Sources/Panels/Panel.swift:7-26` and `82-85` | ~15 lines | 6 | Medium. One central enum |
| `PanelContentView.renderedPanel` arm, `Sources/Panels/PanelContentView.swift:55` | ~20 lines | 4 | Medium |
| `SurfaceKind` static, `Packages/macOS/CmuxWorkspaces/Sources/CmuxWorkspaces/Core/Values/SurfaceKind.swift:18-53` | ~2 lines | 3 | Low |
| Creation method on `Workspace`, beside `newAgentSessionSurface` at `Sources/Workspace.swift:11031` | ~40–80 lines, calling the package | 159 | High. Keep the method a constructor call |

Total in these files: on the order of 150 lines if the creation method is
included. No open-ended registry exists; missing one site is a compile
error or a pane that will not restore.

`CMUXProjectModel` stays the Xcode pane. Do not store the workbench project
there.

### 2. Panel registration

Same files as the row above, plus session payload.

| Site | Estimate | 30-day commits | Risk |
| --- | --- | --- | --- |
| Optional payload on `SessionPanelSnapshot`, `Sources/SessionPersistence.swift:1757-1792`, and a small `Codable` struct next to `SessionAgentSessionPanelSnapshot` | ~40 lines | 18 | Medium. Unknown `PanelType` throws, so older builds cannot read the new snapshot |
| `v2PanelType(rawToken:)` if the socket may create the pane, `Sources/TerminalControllerV2ParamParsingSupport.swift:189-208` | ~5 lines | Not in the hot-file table; treat as a small parser edit | Low if omitted. Omit until a socket client must create the pane |

The persistent id is `SessionPanelSnapshot.id`. The payload carries view
kind and project id. Details are in
[react-panel-hosting.md](react-panel-hosting.md#panel-identity-across-restore).

### 3. Agent-session association

Consume hook sessions and agent events that cmux already records. Do not
edit `CLI/cmux.swift` (221 commits in 30 days).

| Site | Estimate | 30-day commits | Risk |
| --- | --- | --- | --- |
| New listener in the bridge package | New files | 0 | Low |
| Wire the listener from `applicationDidFinishLaunching`, `Sources/AppDelegate.swift:1691` | ~30 lines | 197 | High file, small hunk. A neighbor edit will conflict |

Association means: this cmux agent-session panel id, or this terminal's
hook session, refers to this project id. It does not mean a second agent
runtime.

### 4. Event forwarding

Call `CmuxEventBus.subscribe` (`Sources/CmuxEventBus.swift:471`). Do not
change the buffer constants at lines 258-263 (4 commits, low risk if those
lines stay untouched).

The bridge publishes translations under new event names. Adding a name
constant is a small edit; leaving the names in the bridge and passing them
into `subscribe` avoids editing the bus. Studio's event schema is unread,
so the mapping is not specified here. cmux `seq` and `boot_id` stay the
authority. See the event section of ADR 0001.

### 5. App lifecycle

| Site | Estimate | 30-day commits | Risk |
| --- | --- | --- | --- |
| Start in `applicationDidFinishLaunching` (`AppDelegate.swift:1691`) and stop in `applicationWillTerminate` (`AppDelegate.swift:2573`) | ~40 lines | 197 | High file, small hunk |
| Supervisor, backoff, and ready handshake | The bridge package | 0 | Low in cmux. Behavior depends on Studio, which is unread |

If ADR 0001 selects option A, this row shrinks to "no child process." The
panel host still uses rows 1–4.

## Build gates

Commands already listed in `reports/phase-0/baseline-results.json` are
classified there. Summary:

| Gate | What it can prove |
| --- | --- |
| Linux | `python3 scripts/verify-local.py` for the checks that do not read BUSL paths, `git diff --check`, and the Ghostty pin lookup. This environment ran those. They do not compile the app. |
| Mac, Command Line Tools only | `swift build` / `swift test` for SwiftPM packages, and `node` / `pnpm` for Studio once the tree is present. The Command Line Tools include the macOS SDK. They do not include `xcodebuild`. Packages that import AppKit can still be built with `swift test` on a Mac. They cannot be built on this Linux host. |
| Full Xcode | `xcodebuild`, `./scripts/setup.sh`, `./scripts/reload.sh`, `./scripts/test-unit.sh`, CLI and UI test schemes. `.xcode-version` is `26`. |

GhosttyKit's `zig build` needs Zig 0.16.0 and a Mac. It is not a Command
Line Tools command and it is not `xcodebuild`. Leave it off both of those
gates.

### CI proposal (do not enable)

This is a proposal. Do not add a file under `.github/workflows/`, do not
change `main`, and do not dispatch a run.

Upstream `ci.yml` calls `ci-macos.yml`. On a repository whose owner is not
`manaflow-ai`, the `runs-on` expressions that were read select GitHub-hosted
`ubuntu-24.04`, `macos-26`, or `macos-15` before the Blacksmith labels
(`ci.yml:60`, `ci-macos.yml` admission `runs-on` at line 306, package tests
at line 3574, release-build at line 4401). Fork pull requests do not receive
repository variables (`ci.yml:42-44`). `CI_CACHE_R2_PUBLIC_URL` falls back
to `https://ci-cache.cmux.com`. The owned-head list is
`["manaflow-ai/cmux", "teamleaderleo/cmux"]` (`ci.yml:47`). This fork is not
on that list.

`secrets.GLAEDA_ROUTE_APP_KEY` appears in `ci-macos.yml` (lines 188, 253,
267) on jobs gated by `github.repository_owner == 'manaflow-ai'` (line 226).
A fork run that stays on the `repository_owner != 'manaflow-ai'` branch of
the expression does not need that secret and does not need Depot or Warp.
Depot shows up as a runner-label check around `ci-macos.yml:3952`. Warp is
a cache-backend input on `ci.yml`, not a runner. Those paths are upstream
pool behavior. Reusing the full router on the fork still pulls in admission
placement, the owned-head logic, and labels other than `macos-latest`.

GitHub-hosted macOS minutes are billed on a private repository. That is a
cost property of `macos-latest` / `macos-26`, separate from Depot,
WarpBuild, or Blacksmith.

A minimal workflow that builds and unit-tests, proposed and not added:

```yaml
name: agentflow-macos-unit
on:
  workflow_dispatch:
jobs:
  unit:
    runs-on: macos-latest
    timeout-minutes: 120
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      - name: Require Xcode 26
        run: |
          set -euo pipefail
          # .xcode-version in this repo is 26. macos-latest is not that pin.
          # Fail closed when the image's selected Xcode is older.
          xcodebuild -version
          grep -q '^26' .xcode-version
          xcodebuild -version | head -1 | grep -q 'Xcode 26'
      - name: Metal toolchain
        run: xcodebuild -downloadComponent MetalToolchain
      - name: Unit tests
        env:
          CMUX_DEV_BACKEND_MODE: local
        run: |
          ./scripts/test-unit.sh -derivedDataPath "$PWD/.build/contributor-tests" build-for-testing
          ./scripts/test-unit.sh -derivedDataPath "$PWD/.build/contributor-tests" test
```

`macos-latest` is what was asked for. The Xcode 26 check is there because
this repo's `.xcode-version` is `26`, and upstream's hosted Mac jobs ask for
`macos-26` rather than `macos-latest`. If `macos-latest` does not carry
Xcode 26, the honest substitute is `runs-on: macos-26`, still GitHub-hosted,
still without the upstream router. `./scripts/setup.sh` and a GhosttyKit
build are out of this minimal job; `test-unit.sh` is the unit-test entry
documented for scheme `cmux-unit`. A green run of that job would still not
cover UI tests or a tagged `reload.sh` launch.

Do not point this proposal at BUSL packages, Depot, WarpBuild, Blacksmith,
or `GLAEDA_ROUTE_APP_KEY`.

## Explicitly not in Phase 1

- Rewriting Studio's React UI in SwiftUI.
- A second project database, unless the Studio checklist shows why reuse
  is impractical.
- Edits under the BUSL paths named in `LICENSE`.
- A Ghostty pin move, a second terminal, or a remote-relay allowlist entry.
- Enabling GitHub Actions on the fork.
