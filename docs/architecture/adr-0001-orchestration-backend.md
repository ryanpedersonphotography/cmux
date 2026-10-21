# ADR 0001: Orchestration backend

**Status: recommendation, awaiting approval.** Phase 1 does not start from
this record. The recommendation is a staged hybrid that ends at option B.
Option A is not recommended.

Audited cmux baseline: `72a39c338ef6e4d37e9ab29892f6561df1527781`.

Studio snapshot: a `git archive` of `35a0d1af631a53958883e61c1b98ab072195b11c`,
extracted at `/tmp/agentflow-studio`. The archive has no `.git`, so this
environment did not recompute that SHA. It was not committed into cmux, and
nothing was pushed to the Studio repository.

## Recommendation

Supervise AgentFlow Studio's existing Next.js server as a local Node
process. Keep its libSQL file as the only project database. Host its React
UI in a cmux `WKWebView` pointed at that server. Do not add a second
SQLite file. Do not rewrite the UI in SwiftUI. Do not ship Electron inside
cmux.

Do this in two stages:

1. **Dev supervision, no bundling.** The cmux app starts the user's existing
   Studio checkout with plain Node (`pnpm dev` or `next start`), sets
   `GROKBOT_DATA_DIR`, and waits for `/api/health`. A panel loads
   `http://127.0.0.1:<port>`. Studio's sources stay on disk where the user
   already has them. They are not copied into this repo.
2. **Ship the server inside the app only after a license grant.** Replace
   Electron's `utilityProcess` with a plain Node child running Next's
   standalone `server.js` directly. Drop `apps/desktop`. Bundle a Node
   binary and the libSQL addon built for that Node, not for Electron.

Option A (an in-process Swift package and a new SQLite file) stays
available only if the user rejects running Node. The store below is
practical to reuse, so A is not the default.

## Evidence that the backend runs without Electron

`pnpm dev` is `turbo run dev --filter=@grokbot/web`, which is
`next dev` on `127.0.0.1:3300` (`package.json`, `apps/web/package.json`).
No Electron import exists under `packages/` or `apps/web` or `apps/cli`.

The desktop app is a shell around that server:

- `apps/desktop/src/main/server.ts` forks Next's standalone
  `apps/web/server.js` in an Electron `utilityProcess` and polls
  `/api/health` until `body.app === "grokbot"` (60 s budget).
- `apps/desktop/src/main/index.ts` then calls `BrowserWindow.loadURL` on
  `http://127.0.0.1:<port>`. The preferred port is 47331
  (`apps/desktop/src/main/port.ts`).
- Crash restart is 1 s, then 5 s, then 15 s, and it stops after three
  crashes inside two minutes (`apps/desktop/src/main/restart.ts`).

One Electron file refuses to run as plain Node:
`apps/desktop/src/main/server-host.ts` exits unless
`process.parentPort` exists, which is the utility-process channel. That
file is the packaged host, not the engine. `next dev`, `next start`, and
Next's own `server.js` do not use it. A cmux supervisor should spawn those,
not `server-host`.

On 2026-10-21, in the extracted tree, with Node v22.23.3 and pnpm 12.8.1:

| Command | Exit | Result |
| --- | --- | --- |
| `pnpm install --frozen-lockfile` | 0 | 1,176 packages, 7.3 s |
| `pnpm typecheck` (`turbo run typecheck`) | 0 | 22 packages, 42.6 s |
| `pnpm test` (`turbo run test`) | 0 | 21 tasks, 17.6 s |

`apps/e2e` exposes `test:e2e`, not `test`, so `pnpm test` did not run it.
Desktop tests passed under Vitest with an Electron stub. That does not
launch the Electron binary. The engine tests do not import Electron.

## Verified capabilities

| Claim | Result | Where |
| --- | --- | --- |
| pnpm/turbo monorepo | Yes | Root `package.json` (`packageManager`: pnpm@12.8.1), `pnpm-workspace.yaml`, `turbo.json`. Workspace: `apps/*`, `packages/*` |
| React UI | Yes. Next.js 16 App Router, React 19 | `apps/web`. Routes under `apps/web/app/(app)/` |
| TypeScript/Node backend | Yes. The Next server plus workspace packages | `apps/web`, `packages/*`. CLI is `apps/cli` |
| Electron packaging | Yes, optional shell | `apps/desktop` (`electron` 44.5.1, `electron-builder`). Product name "AgentFlow Studio" |
| Workflow execution | Yes | `packages/orchestrator/src/workflows/runner.ts` (`createWorkflowRunner`) |
| Persistence | Yes. One libSQL `documents` table | `packages/db/src/index.ts`. Default URL `file:./data/grokbot.db` or `GROKBOT_DATABASE_URL` |
| Claude Code adapter | Yes. SDK and CLI | `packages/harness-coding/src/claude/sdk.ts`, `claude/cli.ts`. Ids from `plugin.ts`: `claude-code`, `claude-code-cli` |
| Codex adapter | Yes. SDK and CLI | `packages/harness-coding/src/codex/sdk.ts`, `codex/cli.ts`. Ids: `codex`, `codex-cli` |
| Agent teams | Yes | `packages/core/src/entities/team.ts` (`AgentTeam`). Runner: `packages/orchestrator/src/teams/runner.ts` |
| Git worktrees | Yes | `packages/projects/src/slices/workspace/git.ts` (`git worktree add` / `remove`). Default directory `~/agentflow-studio/workspaces` (`service.ts` `DEFAULT_WORKTREES_DIR`) |
| Approval gates | Yes, and they are the workflow kind | `packages/orchestrator/src/workflows/steps/control.ts` (`kind: "approval"`). See below |
| Project management | Yes | `packages/projects` kernel and slices (agents, memory, workspace, tasks, knowledge, notes, milestones). Entity: `packages/core/src/entities/project.ts`. UI: `apps/web/app/(app)/projects/` |
| MCP | Yes. Client and a server route | Client: `packages/connectors/src/runtime/` (`@modelcontextprotocol/sdk`). Server: `apps/web/app/api/mcp/route.ts` (ChatGPT bridge, Streamable HTTP) |

Gemini CLI is a fifth coding harness in the same plugin. It was not one of
the claims. It is real (`packages/harness-coding/src/gemini/cli.ts`).

## Persistence is the project database

`createDatabaseStore` opens libSQL, sets WAL on local files, and stores
every collection as JSON in `documents (collection, id, data)`. Core
collections include `projects`, `teams`, `workflows`, `workflowRuns`,
`agents`, and `sessions` (`packages/core/src/entities/index.ts`). Slice
collections such as `tasks` (`packages/projects/src/slices/tasks/entities.ts`)
and `worktrees` use the same table. `better-sqlite3` is not a dependency.
`pnpm-workspace.yaml` sets `allowBuilds.better-sqlite3` to false. The
native addon is `@libsql/client`.

A second Swift SQLite file would be a second authority for the same
projects, tasks, and runs. This audit did not find a reason that makes
that necessary. cmux's existing files (`session-*.json`, the agent
journal, `cmux-sync.sqlite3`) stay what they are. They are not this store.

Busy timeout is 5 s (`packages/db/src/index.ts`). Two processes writing
the same file will contend. The supervisor should run one server against
the file.

## Electron couplings

Every import of `electron` is under `apps/desktop`:

| File | What it uses |
| --- | --- |
| `src/preload/index.ts` | `contextBridge`, `ipcRenderer`. Exposes `window.agentflow` and `window.agentflowShell` |
| `src/main/ipc.ts` | `ipcMain`, `BrowserWindow`, `dialog`, `shell`. Channels: pick folder, open external, shell state, retry, choose data dir, open logs, reveal data dir, quit. Each handler checks the sender frame |
| `src/main/index.ts` | `app`, `BrowserWindow`, `Menu`, `session`, `shell`, `Tray`. `app.getPath("userData")` for `desktop.json` and `logs/server.log`. `app.whenReady` |
| `src/main/window.ts` | `BrowserWindow`, preload, `contextIsolation`, `sandbox`, `nodeIntegration: false`. Loads the shell, then the server origin |
| `src/main/menu.ts` | `app`, `BrowserWindow`, `Menu`, `Tray` |
| `src/main/tray-icon.ts` | `nativeImage` |
| `src/main/session.ts` | `Session` type |
| `src/main/server.ts` | `utilityProcess.fork` of the server host |
| `src/main/shell-protocol.ts` | `protocol.registerSchemesAsPrivileged`, `session.protocol.handle` for `afstudio-shell://shell` |
| `src/main/server-host.ts` | No Electron import. Exits without `process.parentPort` |

`app.getPath` is only the desktop config and log directory. The server's
data directory is `GROKBOT_DATA_DIR`, passed in the child environment
(`apps/desktop/src/main/data-dir.ts`). The web app does not call
`app.getPath`.

The preload is optional for the product UI. `apps/web/features/shell/desktop.ts`
reads `window.agentflow` and treats it as absent in a browser. Folder
pick and "open external" are the pieces a Swift bridge would replace
when the desktop shell is gone. Boot, first-run, recovery, and
dev-waiting screens live in `apps/desktop/src/renderer` and are not the
product UI.

Native ABI: the Mac standalone trace in `apps/web/next.config.ts` pulls
`@libsql/darwin-arm64`, `@anthropic-ai/claude-agent-sdk-darwin-arm64`, and
`@openai/codex` darwin binaries into the app. Those are Node addons and
CLI binaries, selected by OS, not compiled against Electron in this repo.
A plain Node child must load the build that matches its ABI. This Linux
install resolved the linux-x64 variants and the tests passed.

## Approval gates inside Studio

An `approval` step pauses the workflow in `waiting-approval` until
`approve(runId, stepId)` (`control.ts`). That is a harness gate between
steps. It does not reach into a running CLI and cancel a tool.

Agent tool approvals are a different gate, and Studio says they cannot be
answered during workflows, routines, or team runs. `PendingApprovals` in
`packages/orchestrator/src/agents.ts` stops the turn and does not run the
tool. The message tells the user to run the task from chat. The Claude
CLI harness passes `--permission-prompts none`
(`packages/harness-coding/src/claude/cli.ts`) because a background run
cannot answer a prompt. Codex passes `--config approval_policy=...`
(`codex/cli.ts`). Chat is where a person can approve a tool. A workflow
step cannot.

## Transport, supervision, events

Stage 1 uses the server Studio already binds: loopback HTTP. The desktop
token (`x-grokbot-desktop`) is installed only through the utility-process
handshake (`server-host.ts`, `apps/web/lib/server/request-guard.ts`). A
`next dev` process does not install it. Loopback origin checks still
apply. The WKWebView should be allowed to navigate only to that origin.
Do not point it at the cmux control socket, and do not open
`SocketControlMode` past `cmuxOnly` to make this work.

When a shipped build needs the desktop token, install it without
`parentPort`. That is a small Studio-side change, not part of this audit's
code.

Restart policy to copy: the delays in `restart.ts`. On restart, Studio
already fails queued and running workflow runs that this process is not
executing, and it leaves approval pauses alone
(`WorkflowRunnerService.recoverInterrupted`). The bridge should not invent
a second recovery.

cmux `seq` / `boot_id` stay the authority for cmux events
(`CmuxEventBus.swift:258-263`). Studio has its own bus (`workflow.run`,
`workflow.step`, `workflow.event` in `runner.ts`). Mapping those into
cmux events is stage-1 bridge work. The child does not assign `seq`.

Startup: the desktop host allows 60 s (`HEALTH_TIMEOUT_MS`). This audit
did not measure a cold `next dev`. The panel should show a starting state
until `/api/health` succeeds.

## License and GPL bundling

No `LICENSE` file exists anywhere in the archive. No `package.json` in the
root or in any workspace package has a `license` field. The only
"copyright" string is a sentence in a seeded persona
(`packages/concierge/src/seed/agents.ts`), not a grant. Treat Studio as
all rights reserved, owned by the user, until the user says otherwise.

cmux's app and CLI are GPL-3.0-or-later. This is an engineering
constraint, not a legal opinion.

The user is the copyright holder of Studio, so they are the person who can
grant a license for it. They cannot drop the GPL from cmux. If a cmux
build ships Studio inside the app bundle and launches it as the app's
backend, that distribution is one combined program. Recipients of a GPL
binary are entitled to the corresponding source of the GPL work, and the
Studio copyright holder has to license the Studio bits they ship under
GPL-3.0-or-later, or under another license that GPL-3.0 can combine with,
for that distribution. The user can make that grant. The archive does not
make it.

Until that grant exists, do not copy Studio into this repository and do
not place it in the `.app`. Stage 1 avoids that: it runs the checkout the
user already has. Stage 2 is the point at which the grant has to exist.
Do not copy Studio into any BUSL path.

## Comparison

| Question | A. In-process Swift, new SQLite | B. Supervised Studio server | Staged hybrid (recommended) |
| --- | --- | --- | --- |
| Project database | A new file. Splits authority with `grokbot.db` | Studio's libSQL file | Same as B |
| React UI | Would still have to host Studio or rewrite it. Rewrite is rejected | WKWebView at the server origin | Same as B |
| Electron | None | Must be removed from the launch path | Stage 1 never starts it. Stage 2 deletes the dependency |
| Plain Node | Not used | `next dev` / `next start` / standalone `server.js` work. `server-host.ts` does not | Stage 1 uses `next dev` or `next start`. Stage 2 uses `server.js` under plain Node |
| GPL | New Swift in this repo is already GPL | Bundling needs the user's grant | Stage 1 does not distribute Studio. Stage 2 needs the grant |
| Node in the bundle | No | Yes, at ship time | Stage 2 only |
| Startup | No Node process | Next.js listen. Health budget in the desktop host is 60 s. Untimed here | Same |

## What approval needs to accept

1. Stage 1 may supervise the user's Studio checkout. No second database.
   No Electron window. No Studio sources in the cmux tree.
2. Stage 2 waits on an explicit license grant before any Studio bits are
   placed in the app bundle.
3. Option A is not the path unless the user refuses a Node child.
