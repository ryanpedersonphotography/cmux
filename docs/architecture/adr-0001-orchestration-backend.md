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

1. **Dev supervision, no bundling.** The cmux app starts one trusted Studio
   checkout with plain Node. The default runtime is `next build`, then
   `next start` (`apps/web/package.json:6-8`). `next dev` is a separate
   developer switch. The supervisor sets `GROKBOT_DATA_DIR` and waits for an
   authenticated ready response, not for an open `/api/health`. A panel loads
   `http://127.0.0.1:<port>` only after that. Studio's sources stay on disk
   where the user already has them. They are not copied into this repo.
   The concrete work items, including the auth choice that is still open,
   are in [stage-1-plan.md](stage-1-plan.md). The earlier "cmux-only, no
   token" wording of this stage is withdrawn.
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
`pnpm-workspace.yaml` sets `allowBuilds.better-sqlite3` to false.
`@libsql/client` is the JavaScript client imported by
`packages/db/src/index.ts`. The native package the standalone trace names
is `@libsql/darwin-arm64` (`apps/web/next.config.ts:27-33`).

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

Agent tool approvals are a different gate. Orchestrator workflows, routines,
and the orchestrator team runner cannot answer them. `runAgentPrompt`
(`packages/orchestrator/src/agents.ts:136-143`) and
`packages/orchestrator/src/teams/context.ts:141-168` use `PendingApprovals`
and do not run the tool. The Claude CLI harness passes
`--permission-prompts none` (`packages/harness-coding/src/claude/cli.ts`)
because a background run cannot answer a prompt. Codex passes
`--config approval_policy=...` (`codex/cli.ts`). A workflow step cannot
stop a tool that has already started.

Chat and room team turns can. `captureMemberApprovals`
(`packages/engine/src/turn.ts:399-439`) keeps one member's pending call and
records the others as denied. `rooms.test.ts:286-305` continues that member
after `approvals.respond`.

## Transport, supervision, events

Stage 1 uses the server Studio already binds: loopback HTTP. That server
currently allows every request when no desktop token is installed
(`desktopTokenProblem`, `apps/web/lib/server/request-guard.ts:86-87`).
Loopback origin checks do not replace a capability. The WKWebView navigates
only to the supervisor's exact origin. Do not point it at the cmux control
socket, and do not open `SocketControlMode` past `cmuxOnly` to make this
work.

How the capability is installed is an open user choice, compared in
[stage-1-plan.md](stage-1-plan.md#open-decision-how-the-capability-is-checked).
The recommendation is a small Studio change: call `installDesktopToken`
before listen, from a pipe rather than `process.env` or
`process.parentPort`, and accept the value as an HttpOnly cookie. An
authenticated proxy that leaves Studio's TCP port open does not deny a
second local process. Electron's `installSession`
(`apps/desktop/src/main/session.ts:16-24`) is the behavior to match, not a
header on the first navigation.

Restart policy to copy: `restartDelay` in `restart.ts` (1s, 5s, 15s, then
stop). On restart, Studio already fails queued and running workflow runs
that this process is not executing, and it leaves approval pauses alone
(`WorkflowRunnerService.recoverInterrupted`). The bridge should not invent
a second recovery. The supervisor also drains logs, kills the process
group, and shares one data-directory lock with Studio Desktop. Those items
are S5 in the stage 1 plan.

cmux `seq` is durable (`CmuxEventSequenceStore`). `boot_id` is this cmux
process (`CmuxEventBus.swift:281`). Studio has its own bus. The live HTTP
stream is `GET /api/events`, and `eventResponse` does not replay
(`apps/web/features/events/stream.ts:26-27`). The bridge refreshes Studio
state on connect, then may publish into cmux under cmux's allocator. The
child does not assign `seq`. A header named `workflow.run` is not that
transport.

Startup: the desktop host allows 60 s (`HEALTH_TIMEOUT_MS`). This audit
did not measure a cold `next build` or `next start`. The panel shows a
native starting shell until an authenticated ready response, and it does
not treat `body.app == "grokbot"` as identity. `/api/health` also returns
`onboarded` (`apps/web/app/api/health/route.ts:10-13`) and is token-exempt.

## License and GPL bundling

This section is a reading of the files, not a legal conclusion.

No `LICENSE` file exists anywhere in the archive. No `package.json` in the
root or in any workspace package has a `license` field. The only
"copyright" string found is a sentence in a seeded persona
(`packages/concierge/src/seed/agents.ts`), not a grant. The files do not
show a license, and they do not show that the user owns every contribution
in the tree.

cmux's app and CLI are GPL-3.0-or-later. The GPL on those files is not
something this fork can drop.

Whether shipping Studio inside a cmux bundle forms one combined work, and
what a grant would have to say, is for the user and counsel. This audit
does not decide it. Until the user decides, do not copy Studio into this
repository and do not place it in the `.app`. Stage 1 runs a checkout the
user already has. Stage 2 is the point at which ownership, a written grant,
dependency and native-binary notices, and corresponding source have to be
settled. Do not copy Studio into any BUSL path.

## Comparison

| Question | A. In-process Swift, new SQLite | B. Supervised Studio server | Staged hybrid (recommended) |
| --- | --- | --- | --- |
| Project database | A new file. Splits authority with `grokbot.db` | Studio's libSQL file | Same as B |
| React UI | Would still have to host Studio or rewrite it. Rewrite is rejected | WKWebView at the server origin | Same as B |
| Electron | None | Must be removed from the launch path | Stage 1 never starts it. Stage 2 deletes the dependency |
| Plain Node | Not used | `next dev`, `next start` after `next build`, and standalone `server.js` are separate commands. `server-host.ts` does not import Electron | Stage 1 default is `next build` then `next start`. `next dev` is a developer switch. Stage 2 uses `server.js` under plain Node. `next build` and `next start` were not run in this audit |
| GPL | New Swift in this repo is already GPL | The files contain no grant. Whether a bundle is a combined work is for the user and counsel | Stage 1 does not distribute Studio. Stage 2 waits on that decision |
| Node in the bundle | No | Yes, at ship time | Stage 2 only |
| Startup | No Node process | Next.js listen. Health budget in the desktop host is 60 s. Untimed here | Same |

## What approval needs to accept

1. Stage 1 may supervise the user's Studio checkout. No second database.
   No Electron window. No Studio sources in the cmux tree.
2. Stage 2 waits on the user and counsel before any Studio bits are placed
   in the app bundle. The archive is not a grant, and it is not evidence
   that the user owns every contribution.
3. Option A is not the path unless the user refuses a Node child.
