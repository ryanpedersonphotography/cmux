# ADR 0001: Orchestration backend

**Status: withheld. Not approved.** Phase 1 does not start from this record.
The previous recommendation (an in-process Swift package with its own SQLite
file) is withdrawn as the default. It is not replaced by a selection of
AgentFlow Studio's backend. Neither option has the evidence this addendum
requires.

Audited cmux baseline: `72a39c338ef6e4d37e9ab29892f6561df1527781`.

## Decision

Do not choose an orchestration backend until AgentFlow Studio's tree has been
read. Do not add a second authoritative project database on the strength of
the Phase 0 proposal. Do not claim that Studio's TypeScript backend can run
without Electron, and do not claim that it cannot.

## Evidence

Requested repository: `https://github.com/ryanpedersonphotography/agentflow-studio`
(private). Requested revision: `35a0d1af631a53958883e61c1b98ab072195b11c` or
later. That SHA was not resolved.

On 2026-10-21, from this checkout, with `gh` authenticated as the Cursor
GitHub App installation for `ryanpedersonphotography/cmux`:

| Command | Exit | Result |
| --- | --- | --- |
| `gh repo clone ryanpedersonphotography/agentflow-studio /tmp/audit-external/agentflow-studio -- --branch main` | 1 | `GraphQL: Could not resolve to a Repository with the name 'ryanpedersonphotography/agentflow-studio'.` |
| `gh api repos/ryanpedersonphotography/agentflow-studio` | 1 | HTTP 404, `Not Found` |
| `git ls-remote https://github.com/ryanpedersonphotography/agentflow-studio.git 35a0d1af631a53958883e61c1b98ab072195b11c` | 128 | `remote: Repository not found.` |

The installation can see public repositories under
`ryanpedersonphotography`. It cannot see this private repository. No file
from Studio was read. `pnpm` and Node `v22.23.3` are installed here;
`pnpm install`, typecheck, and tests were not run because there was no tree.
The Studio repository was not modified and was not pushed to.

These reported properties are therefore **unverified**. Each one still needs
a path in Studio's tree:

- pnpm/turbo monorepo
- React UI
- TypeScript/Node backend
- Electron packaging
- workflow execution
- persistence
- Claude Code adapter
- Codex adapter
- agent teams
- git worktrees
- approval gates
- project management
- MCP integration
- a `LICENSE` file and its terms

## Electron independence (unanswered)

The question is whether Studio's workflow engine, persistence, project model,
agent adapters, and MCP services can run as a plain Node process with no
Electron main process.

This audit cannot list couplings it did not see. The inventory that a later
pass must fill, with file paths, is:

- `ipcMain` / `ipcRenderer`
- preload scripts
- `app.*`, including `app.getPath`
- `BrowserWindow` and other Electron window types
- native modules built against Electron's ABI (`better-sqlite3` and anything
  else under `node_modules` that uses Node-API against Electron's headers)
- any path that exists only after Electron has started

Until that list exists, option B is a hypothesis.

## Option A — in-process Swift package and a new SQLite file

This is what [target-architecture.md](target-architecture.md) recommended
before this addendum. The shape, as a description of that proposal:

- A new Swift package in this GPL tree. The cmux process owns it.
- The package imports Foundation and SQLite3. It does not import AppKit,
  SwiftUI, Ghostty, WebKit, or `CmuxControlSocket`.
- Project identity, plans, and workflow state live in a new SQLite file under
  Application Support, separate from `session-<bundleId>.json`,
  `agent-journal-<bundle>.sqlite3`, and `cmux-sync.sqlite3`.
- cmux stays the authority for windows, workspaces, panes, terminals, and Feed.

What the addendum changes: a second authoritative project database is allowed
only when reusing Studio's persistence is shown to be impractical. That
showing has not happened, because Studio's persistence was not read. Option A
stays on the table as a fallback. It is not the decision.

Option A also does not, by itself, host Studio's React UI. The addendum
rejects a SwiftUI rewrite of that UI. If Studio's screens are the UI, option
A still needs the panel host in
[react-panel-hosting.md](react-panel-hosting.md), and those screens may call
Electron IPC or a Studio API that this audit has not seen.

## Option B — Studio's backend as a supervised local service

The shape, as a constraint on a later design. None of the Studio-side cells
are confirmed.

cmux launches one child process and supervises it. The child has no
`BrowserWindow`. A small Swift bridge package owns project navigation, event
subscriptions, panel registration, and lifecycle. Studio's React stays the
UI and is hosted as in [react-panel-hosting.md](react-panel-hosting.md).
Studio's store, if it can be opened without Electron, is the project
database. cmux does not open a second one.

### Transport

Prefer a Unix socket the parent creates, mode `0600`, in a directory the
parent owns. The alternative is `127.0.0.1` with a token generated per
launch, passed on the child's argv or over the socket, and checked on every
request. Do not reuse the cmux control socket. That socket defaults to
`SocketControlMode.cmuxOnly` (`SocketControlSettings.swift:81-84`); opening
it to `automation` or `password` admits every same-UID client, which is wider
than one supervised child. Remote relay stays default-deny
(`RemoteRelayCommandPolicy.swift:81-88`). The bridge does not assume the
child is reachable through `cmux ssh`.

Whether Studio already speaks either transport is unverified.

### Supervision and crash recovery

Start the child from `applicationDidFinishLaunching`
(`Sources/AppDelegate.swift:1691`) and stop it from
`applicationWillTerminate` (`Sources/AppDelegate.swift:2573`). The supervisor
itself lives in the bridge package. The app delegate only calls start and
stop.

On a child exit, restart with backoff. Each successful start mints a new
`boot_id` for the bridge's view of the child. In-flight workflow steps are
not assumed to have finished. The bridge marks them unknown and reconciles
from Studio's store after the child is up again. That reconciliation
procedure does not exist until the store has been read.

A child crash must not be reported as a cmux crash, and a cmux crash is not
recovered by this supervisor.

### Startup latency

Not measured. A Node process plus a TypeScript server often takes longer
than an in-process Swift open of SQLite. The number belongs in a later run
of the real binary. Do not budget the panel on a guessed duration. The panel
can show a starting state until the bridge receives the child's ready event.

### One event protocol

cmux's event log is the sequence authority: monotonic `seq`, `boot_id`,
in-memory replay of 4,096 events, `resume.gap` when the cursor is stale
(`CmuxEventBus.swift:258-263`, `subscribe` at line 471). Studio's own event
shape was not read, so there is nothing to map yet.

When a shape exists, the bridge assigns cmux `seq` values. It does not let
the child pick `seq` or `boot_id`. A subscriber that resumes after a child
restart sees a gap or a new `boot_id` and refreshes with a snapshot, the same
rule `events.stream` already uses. Two streams (cmux's bus and Studio's bus)
both exist until that mapping is implemented. The mapping is a translation
at the bridge, not a second log that clients have to merge.

Buffer sizes in `CmuxEventBus` stay as they are. Studio events that do not
fit the 16 KiB frame are summarized and fetched by id.

### GPL and bundling

cmux's app and CLI are GPL-3.0-or-later. See `LICENSE` and
[upstream-compatibility.md](upstream-compatibility.md). This is an
engineering constraint, not a legal opinion.

Studio's license was not opened. Bundling Studio inside a GPL app is
undecided until that file is read:

- A GPL-compatible license (MIT, BSD, Apache-2.0, GPL-3.0) can be distributed
  with this tree if the notices travel with the bits. Apache-2.0 combines
  with GPL-3.0, which is the license this repo states.
- A proprietary license, the Business Source License, a non-commercial
  license, or AGPL changes the answer. AGPL in particular reaches network
  use. BUSL code in the upstream cmux tree is already out of bounds for this
  work; Studio is a separate question and was not classified.
- Shipping Studio as a subprocess inside `Cmux.app` is still distribution of
  Studio. A socket between processes does not, by itself, remove that.

Do not copy Studio sources into this repo, and do not copy them into any
BUSL path, before the license is known. This ADR does not vendor anything.

### Packaging Node

Option B puts a Node binary in the app bundle, beside Studio's JavaScript
and any native addons. That binary has to be signed and notarized with the
app. It has to match the Mac architectures the app ships. It is not
Electron's Node. A native addon compiled for Electron's ABI will fail to
load in plain Node; `better-sqlite3` is the usual example, and this audit
did not check whether Studio uses it.

Electron-only APIs (`app.getPath`, `ipcMain`) have to be replaced or shimmed
before the child can start. That work is in Studio or in a thin adapter, and
it is unscoped until the coupling list exists.

The cmux bundle today does not ship Node for this purpose. Adding it is a
packaging change in the release path, which this audit did not design.

## Comparison

| Question | A. In-process Swift, new SQLite | B. Supervised Studio backend |
| --- | --- | --- |
| Reads Studio's code | No | Required, and not done |
| Second project database | Yes. Blocked until Studio's store is shown impractical | Reuses Studio's store if that store can be opened without Electron. Unverified |
| React UI | Does not host it unless the panel work in the hosting note is added | Hosts it. The UI's dependence on Electron is unverified |
| Electron coupling | None from Studio | Unverified. The coupling list above is empty because the tree was closed |
| Startup | No Node process. Latency unmeasured | Node plus Studio. Latency unmeasured |
| Crash | A domain fault is in the app process | Child can restart. Recovery procedure unverified |
| Events | Publish on `CmuxEventBus` in-process | Translate into cmux `seq` / `boot_id`. Studio's events unread |
| Transport | None | Unix socket, or localhost plus a per-launch token. Not the cmux control socket |
| GPL | New Swift in this repo is GPL-3.0-or-later | Depends on Studio's license, which was not read |
| Node in the bundle | No | Yes, plus addon ABI and notarization |

## What would select an option

Select B only if a later read shows all of the following:

1. The workflow engine, persistence, project model, adapters, and MCP entry
   points start in plain Node with the Electron main process absent.
2. The Electron couplings are listed, and each one is either unused on that
   path or replaced by the socket adapter.
3. The persistence schema can be the only project database, opened by that
   process, without a parallel Swift store.
4. The license allows shipping those bits inside a GPL-3.0-or-later app bundle.
5. A real `pnpm` typecheck and test run has exit codes recorded against a
   SHA at or after `35a0d1af631a53958883e61c1b98ab072195b11c`.

Select A only if that read shows the store or the engine cannot be reused,
and the user accepts a new SQLite file as the project authority. Rewriting
Studio's React UI in SwiftUI is not part of A.

Until then the architecture in
[target-architecture.md](target-architecture.md) stays awaiting approval,
and [phase-1-plan-revised.md](phase-1-plan-revised.md) stays a plan.
