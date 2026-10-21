# Phase 1 plan (revised)

**Status: plan only. Not approved. Do not implement it.**

Phase 0 is accepted as an audit. The implementation architecture is not
accepted. The in-process Swift package and the second SQLite file are
withdrawn in
[adr-0001-orchestration-backend.md](adr-0001-orchestration-backend.md).

The stage 1 scope that said "cmux-only edits" and deferred the desktop
token is also withdrawn. Codex's review rejected that scope. The verdicts
are in [review-response-codex-1.md](review-response-codex-1.md). The work
items that replace it are in [stage-1-plan.md](stage-1-plan.md).

Nothing in this plan authorizes a commit that changes `Sources/`, `CLI/`,
packages, workflows, or AgentFlow Studio.

## Stop rule

ADR 0001 recommends a staged hybrid that ends at option B. Phase 1 still
starts only after the user approves
[target-architecture.md](target-architecture.md) and chooses between the
two auth options in the stage 1 plan. This file does not approve either.

## Studio checklist (done)

Archive of `35a0d1af631a53958883e61c1b98ab072195b11c`, extracted outside
this repo. No `.git` in the archive, so the SHA was not recomputed here.
The tree was not modified and was not pushed. Paths and exit codes are in
ADR 0001 and `reports/phase-0/baseline-results.json`.

| Claim | Result |
| --- | --- |
| pnpm/turbo monorepo | Present. Node `>=22.15`, pnpm `12.8.1` |
| React UI | Next.js App Router in `apps/web`. Task board, workflow React Flow, and notes textarea are present. Gantt and Tiptap are not |
| TypeScript/Node backend | `next dev`, `next build`, and `next start` are separate scripts (`apps/web/package.json:6-8`). `next start` needs a matching build. Packages do not import Electron |
| Electron packaging | `apps/desktop` only |
| Native ABI | `@libsql/client` is the JavaScript client. The traced native package is `@libsql/darwin-arm64`. `better-sqlite3` is not a dependency |
| Workflow execution | `createWorkflowRunner` |
| Persistence | One libSQL `documents` table. A second project database is not needed |
| Claude Code and Codex | `packages/harness-coding` SDK and CLI harnesses |
| Agent teams | Orchestrator team runs block tool approvals. Engine chat and room turns can resume one member (`packages/engine/src/turn.ts:399-439`) |
| Git worktrees | `packages/projects/src/slices/workspace/git.ts` |
| Approval gates | Workflow `approval` step. Orchestrator background runs do not answer tools. Room turns can |
| Project management | `packages/projects` and `/projects` |
| MCP | `packages/connectors` client and `apps/web/app/api/mcp/route.ts` |
| License | No LICENSE file. No `license` field in any package.json. The files do not show a grant or that the user owns every contribution |

`pnpm install --frozen-lockfile` exited 0. `pnpm typecheck` exited 0.
`pnpm test` exited 0. `pnpm test:e2e`, `next build`, and `next start` were
not run.

## Where the cmux edits are

They are listed with owners, acceptance tests, and gates in
[stage-1-plan.md](stage-1-plan.md#native-boundaries-corrected). In short:
`PanelType` gains a case and does not gain a decoder arm
(`Sources/Panels/Panel.swift:27-33`); workspace encode
(`Sources/Workspace.swift:616`) and `createPanel` (`:1621`, `:2354`); both
dock switches (`DockSplitStore+SessionSnapshot.swift:442`,
`DockSplitStore+SessionRestore.swift:256`); an optional payload on
`SessionPanelSnapshot`; lifecycle calls in `AppDelegate`. Session schema
version stays 1. Secure stage 1 also changes Studio or adds a proxy. The
cmux-only constraint is incompatible with denying a second local process.

## Build gates

Commands already listed in `reports/phase-0/baseline-results.json` are
classified there. Summary:

| Gate | What it can prove |
| --- | --- |
| Linux | `python3 scripts/verify-local.py` for the checks that do not read BUSL paths, `git diff --check`, and the Ghostty pin lookup. This environment ran those. They do not compile the app. Studio's Vitest guard tests can also run here. |
| Mac, Command Line Tools only | `swift build` / `swift test` for SwiftPM packages, and `node` / `pnpm` for Studio once the tree is present. The Command Line Tools include the macOS SDK. They do not include `xcodebuild`. |
| Full Xcode | `xcodebuild`, `./scripts/setup.sh`, `./scripts/reload.sh`, `./scripts/test-unit.sh`, CLI and UI test schemes. `.xcode-version` is `26`. The app links `GhosttyKit.xcframework`, so this gate includes provisioning that framework. |
| Mac and the GhosttyKit checksum | `./scripts/ensure-ghosttykit.sh` verifies the pinned sha256. Upstream CI uses `./scripts/download-prebuilt-ghosttykit.sh` (`.github/workflows/ci-macos.yml:715-731`). This is not `xcodebuild` and it is not a Command Line Tools package test. A job that runs `test-unit.sh` without it does not build. |

GhosttyKit's own `zig build` needs Zig 0.16.0 and a Mac. The unit-test job
uses the verified prebuilt framework. It does not rebuild Ghostty.

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
a cache-backend input on `ci.yml`, not a runner.

GitHub-hosted macOS minutes are billed on a private repository. That is a
cost property of `macos-26`, separate from Depot, WarpBuild, or Blacksmith.

A minimal workflow that builds and unit-tests, proposed and not added.
`macos-26` is the image because `.xcode-version` is `26`. `macos-latest` is
not that pin.

```yaml
name: agentflow-macos-unit
on:
  workflow_dispatch:
jobs:
  unit:
    runs-on: macos-26
    timeout-minutes: 120
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      - name: Require Xcode 26
        run: |
          set -euo pipefail
          xcodebuild -version
          grep -q '^26' .xcode-version
          xcodebuild -version | head -1 | grep -q 'Xcode 26'
      - name: Verified GhosttyKit
        run: ./scripts/ensure-ghosttykit.sh
      - name: Metal toolchain
        run: xcodebuild -downloadComponent MetalToolchain
      - name: Unit tests
        env:
          CMUX_DEV_BACKEND_MODE: local
        run: |
          ./scripts/test-unit.sh -derivedDataPath "$PWD/.build/contributor-tests" build-for-testing
          ./scripts/test-unit.sh -derivedDataPath "$PWD/.build/contributor-tests" test
```

`ensure-ghosttykit.sh` checks the pinned sha256. A clean runner that cannot
see the published framework fails closed. Upstream's download step
(`download-prebuilt-ghosttykit.sh`, cache key `ghosttykit-sentry-off-v1-<sha>`)
is the alternate when the checksum file expects that archive. Either step
runs before `test-unit.sh`. A green run would still not cover UI tests or a
tagged `reload.sh` launch. Once they exist, the same job runs the supervisor,
snapshot, and web-view security tests from the stage 1 plan.

Do not point this proposal at BUSL packages, Depot, WarpBuild, Blacksmith,
or `GLAEDA_ROUTE_APP_KEY`.

## Explicitly not in Phase 1

- Rewriting Studio's React UI in SwiftUI.
- A second project database. Studio's libSQL file is the authority.
- Copying Studio into this repo, or into the app bundle. The files do not
  contain a grant. Whether a bundle is a combined work is for the user and
  counsel.
- Edits under the BUSL paths named in `LICENSE`.
- A Ghostty pin move, a second terminal, or a remote-relay allowlist entry.
- Enabling GitHub Actions on the fork.
- Treating `/api/health` returning `app: "grokbot"` as proof of which
  process owns the data directory.
