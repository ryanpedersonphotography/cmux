# Phase 1 plan (revised)

**Status: plan only. Not approved. Do not implement it.**

Phase 0 is accepted as an audit. The implementation architecture is not
accepted. This file replaces the Phase 1 sequence that assumed an in-process
Swift package and a new SQLite file. That assumption is withdrawn in
[adr-0001-orchestration-backend.md](adr-0001-orchestration-backend.md).

Nothing in this plan authorizes a commit that changes `Sources/`, `CLI/`,
packages, workflows, or AgentFlow Studio.

## Stop rule

The Studio audit is done. ADR 0001 recommends a staged hybrid that ends at
option B. Phase 1 still starts only after the user approves
[target-architecture.md](target-architecture.md). This file does not
approve it.

## Studio checklist (done)

Archive of `35a0d1af631a53958883e61c1b98ab072195b11c`, extracted outside
this repo. No `.git` in the archive, so the SHA was not recomputed here.
The tree was not modified and was not pushed. Paths and exit codes are in
ADR 0001 and `reports/phase-0/baseline-results.json`.

| Claim | Result |
| --- | --- |
| pnpm/turbo monorepo | Present |
| React UI | Next.js App Router in `apps/web`. Task board, workflow React Flow, and notes textarea are present. Gantt and Tiptap are not |
| TypeScript/Node backend | `next dev` / `next start`. Packages do not import Electron |
| Electron packaging | `apps/desktop` only |
| Native ABI | `@libsql/client`. `better-sqlite3` is not a dependency |
| Workflow execution | `createWorkflowRunner` |
| Persistence | One libSQL `documents` table. A second project database is not needed |
| Claude Code and Codex | `packages/harness-coding` SDK and CLI harnesses |
| Agent teams | `AgentTeam` and `createTeamRunner` |
| Git worktrees | `packages/projects/src/slices/workspace/git.ts` |
| Approval gates | Workflow `approval` step. Tool approvals are not answerable inside a workflow run |
| Project management | `packages/projects` and `/projects` |
| MCP | `packages/connectors` client and `apps/web/app/api/mcp/route.ts` |
| License | No LICENSE file. No `license` field in any package.json. All rights reserved |

`pnpm install --frozen-lockfile` exited 0. `pnpm typecheck` exited 0.
`pnpm test` exited 0. `pnpm test:e2e` was not run.

## After approval, the only cmux edits

The approved path is stage 1 of ADR 0001: a Swift bridge that supervises
the user's Studio checkout and registers panels. Workflow rules, React
screens, and the project store stay in Studio. They do not move into
`Workspace.swift` or `CLI/cmux.swift`.

Diff sizes are estimates from the call sites at
`72a39c338ef6e4d37e9ab29892f6561df1527781`, not measured patches. Conflict
counts are `git rev-list --count upstream/main --since=2026-09-21`.

### 1. Project identity and navigation

cmux workspaces stay layout. The project id is Studio's `projects`
collection (`packages/core/src/entities/project.ts`). The bridge keeps a
side table from workspace UUID to that id. That table is not a new field
on `Workspace` and it is not a second database.

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

Stage 1 starts `next dev` or `next start` here and stops it on terminate.
The child is plain Node, not Electron's `utilityProcess`. Option A would
delete this row. It is not the recommendation.

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
- A second project database. Studio's libSQL file is the authority.
- Copying Studio into this repo, or into the app bundle, before the user
  grants a license for that distribution.
- Edits under the BUSL paths named in `LICENSE`.
- A Ghostty pin move, a second terminal, or a remote-relay allowlist entry.
- Enabling GitHub Actions on the fork.
