# Target architecture

**Status: proposal, awaiting approval.** Phase 0 is an audit. This file is
not an approved implementation architecture. Phase 1 does not start until
this file is accepted. Nothing here is implemented.

Audited baseline: `72a39c338ef6e4d37e9ab29892f6561df1527781`.

The orchestration recommendation is a staged hybrid that ends at Studio's
Next.js server and its libSQL file. It is not approved. See
[adr-0001-orchestration-backend.md](adr-0001-orchestration-backend.md).
The plan that follows approval is
[stage-1-plan.md](stage-1-plan.md). It is a plan only. Stage 1 as first
written is withdrawn; the review is
[review-response-codex-1.md](review-response-codex-1.md).

## Decision

Recommend option B, staged. Do not open a second project database.

Studio's engine runs as plain Node. `pnpm dev` is Next.js on
`127.0.0.1:3300`. Electron is a desktop shell
(`apps/desktop`) that supervises the same server. Persistence is one
libSQL `documents` table (`packages/db/src/index.ts`), default
`file:./data/grokbot.db`. Projects, workflows, teams, tasks, and worktrees
are collections in that file. Reusing it is practical. A new Swift SQLite
file is not the recommendation.

Stage 1 supervises one trusted checkout and does not copy it into this
repo. The archive has no `LICENSE` and no `package.json` `license` field.
That is a reading of the files: there is no grant in the tree, and there
is no evidence here that the user owns every contribution. Whether a later
bundle is a combined work is for the user and counsel. Until that decision,
Studio stays out of the bundle. cmux stays GPL-3.0-or-later. The auth
choice inside stage 1 is still open; the recommendation is a minimal
Studio token change, recorded in
[stage-1-plan.md](stage-1-plan.md#open-decision-how-the-capability-is-checked).

What still holds:

- cmux remains the authority for windows, workspaces, panes, terminals, and
  Feed.
- A workspace id is a reference. It is not, by itself, the project id.
- Domain rules stay out of `Workspace.swift`, `TerminalController.swift`, and
  `CLI/cmux.swift`.
- Studio's React UI stays in React. This proposal does not rewrite it in
  SwiftUI. Hosting is
  [react-panel-hosting.md](react-panel-hosting.md): a dedicated `WKWebView`
  loads the loopback Next origin. `BrowserPanel`, `loadFileURL`, and
  `afstudio-shell://` are the wrong loaders for the product UI.
- Native edits, once this proposal is approved, are the boundaries in
  [stage-1-plan.md](stage-1-plan.md#native-boundaries-corrected). Secure
  stage 1 also changes Studio, or it cannot deny a second local process.

## Why a socket-only companion is the wrong UI shape

A companion over the socket is viable for launching terminals and reading
events, and it is the wrong shape for the panel requirement.

What the socket already gives an outside process, once admission allows it:

- List and create workspaces, panes, and terminals.
- Send text and keys, focus, stream `events.stream` with `seq`, `boot_id`,
  and `resume.gap` (`CmuxEventBus.swift:258-263`).
- Push Feed items.

What it does not give:

- A pane. Types are a closed `switch` (`PanelContentView.swift:55`,
  `Panel.swift:7-26`). There is no RPC that embeds a foreign view.
- Socket access by default. `SocketControlMode.defaultMode` is `.cmuxOnly`
  (`SocketControlSettings.swift:81-84`). A companion needs `automation` or
  `password` mode, which widens who can drive the terminal.
- Release-build approval of Chief cards. Those methods are debug-only.
- Remote shells. `RemoteRelayCommandPolicy` denies unknown methods and
  command parameters (`RemoteRelayCommandPolicy.swift:81-88`).

The plan's Phase 2 gate is a project panel beside a terminal, without a
second window manager. That gate is an in-process panel. A companion window
is a second window manager.

A supervised Studio process with no window of its own is the option B
recommendation in ADR 0001. It is still awaiting approval. The Studio
archive was read at `35a0d1af631a53958883e61c1b98ab072195b11c`.

## Why not "all of it in Workspace.swift"

`Workspace.swift` is already enormous and had 159 commits on `main` in 30
days. `CLI/cmux.swift` had 221 and `TerminalController.swift` had 128.
Project rules in those files would conflict continuously and could not be
tested without the app.

The panel adapter is the edit those hot files get: one `PanelType` case
(no special decoder arm; `Self(rawValue:)` already accepts a new case),
one view branch, the workspace encode and restore switches, both dock
switches, and one creation method that calls out. Workflow transitions
stay in Studio. The boundaries and their sizes are in
[stage-1-plan.md](stage-1-plan.md#native-boundaries-corrected).

## Persistence

Studio's libSQL file is the project authority. Do not open a second one.
ADR 0001 records why reuse is practical.

These existing files stay what they are, and they are not the project store:

- `session-<bundleId>.json` (layout; untrusted imports scrub commands,
  `SessionSnapshotImportTrust.swift:24-60`)
- `agent-journal-<bundle>.sqlite3` (agent events,
  `AgentJournalLifecycleCenter+Database.swift:32-34`)
- `cmux-sync.sqlite3` (team sync)

Do not migrate the journal's schema. Do not store resume commands that the
session layer would auto-exec. Restoring a project shows pending work. It
does not launch agents.

## Embedded UI

No-go on `BrowserPanel`. Go on a new `PanelType` whose `WKWebView` loads
Studio's `http://127.0.0.1:<port>`. The full note is
[react-panel-hosting.md](react-panel-hosting.md).

Lock navigation to that origin, the way the agent-session host locks
navigation to its shell URL. Add the web-content termination reload that
`MarkdownWebRenderer` already has. Do not share the browser profile's
cookie store. `loadFileURL` does not serve this Next.js app.

## Provider gates

Build workflow policy on capabilities the matrix shows, not on the Feed
docs table.

- Claude Code can block in Feed on permission, plan, and question events.
- Gemini and Kiro can block on side-effecting tool hooks.
- OpenCode can block through its plugin.
- Codex hook mode cannot. Codex Teams is a separate app-server bridge and
  stays unverified until Phase 5 reads that reply path.
- Grok, Copilot, CodeBuddy, Factory, Qoder, Kimi, Pi, and the lifecycle-only
  agents cannot block in Feed. A workflow-level gate can withhold the next
  step for those providers. It cannot stop a tool the agent has already
  started. The split is in
  [integration-points.md](integration-points.md#approval-model).

Resume stays on `AgentResumeArgv`. Do not invent a second resume command.
Do not auto-resume from an imported or unapproved binding.

## myzig, as rules for this Swift tree

Studied `hunghg255/myzig` at `4203821d13d63b1c1a9b24ac392145273211bda3`
(MIT). No source was copied. Zig compile-time tricks, the 600-line file
cap, and "no C" are not rules for cmux. `Workspace.swift` already exceeds
any small-file cap; do not rewrite it to satisfy one.

Rules that do apply:

1. Domain types do not import UI or the terminal engine.
2. One implementation of a transition. The panel, the CLI, and a test call
   the same function.
3. Commands and events are typed Swift values. JSON exists only at the
   socket and the database edge.
4. New files stay focused. Do not add project logic to `Workspace.swift`.
5. Domain tests run without a window, a socket, or the user's
   `Application Support` directory.
6. State changes when an event arrives. Do not poll the terminal to invent
   workflow transitions.
7. The domain package does not link Ghostty, WebKit, or the BUSL server code.
8. An idle project store does no timed work.
9. A new dependency needs a reason that existing Foundation or an existing
   package cannot cover. SQLite3 is already in the app.
10. Do not claim a behavior the provider matrix marks unverified.

## Tellurion, ideas only

Studied `steventsvik/Tellurion` at `41a91325f7298baee7957a39757ceae558a8fee8`
(AGPL-3.0). It is a Ghostty fork (Zig 0.15.2 in its `build.zig.zon`) with a
Swift feature layer under `macos/Sources/Features/`. No code was copied.
Do not port its Ghostty tree. cmux's pin is Zig 0.16.0 at `ef4f1570d`.

Worth studying as behavior, already matched or not by cmux:

| Idea | Where Tellurion puts it | What cmux already has | What a later phase might add |
| --- | --- | --- | --- |
| Writer/reviewer rounds | `macos/Sources/Features/Agent Tools/AgentPipelines.swift`. Writer surface, reviewer surface, stages writing/reviewing/finished, round cap, messages wait for Send unless auto-send, and auto-send only types between turns | Separate terminals and Feed. No round state machine | A workflow value in the domain package: roles, round count, explicit stop. Human send stays the default. Do not type into a terminal mid-turn |
| Review inbox | `macos/Sources/Features/Review/ReviewInbox.swift` | Diff viewer, comment socket (`comments.list`) | An inbox projection of domain evidence, not a second diff engine |
| Undo a turn | `TurnCheckpoints.swift`: git tree objects, index untouched, restore is itself reversible | Nothing equivalent in the project sense. Session restore is layout | Snapshots as data the domain records. Do not move HEAD. Confirm before restore |
| Handoff | README: task, recent conversation, diff since the first prompt, failed commands, project memory; modes Continue, Review, Second opinion | `session move` is a Claude session migration, which is a different operation | A structured handoff record. The receiving agent is a new cmux terminal |
| Shared project memory | Hook adds the other provider's notes, labelled as possibly stale | Per-agent memory files, Chief memory | Scoped notes with provenance. Not a hidden prompt injection |
| Code map | Files the agent touched, drawn as a map | Not present | A projection of journal events. Phase 9, not Phase 1 |
| Hooks that do not approve | `agent-hooks/agent-hook.sh` reports status. Its header also rewrites some dev-server commands. The README's "observe only" line is stricter than that script | cmux hooks both observe and, for some providers, block in Feed. Keep Feed. Do not import Tellurion's hook script | None |

Tellurion's terminal is the product. cmux's terminal is protected
infrastructure. Take the workflow ideas. Leave the emulator alone.

## Boundaries that stay even after approval

- No Rust daemon, second terminal, or plugin runtime.
- A Node process is in bounds only as Studio's backend, and only if ADR 0001
  selects it after the license and the Electron coupling list are known.
  This proposal does not add a second Node service beside that one.
- No edits under BUSL paths.
- No Ghostty pin movement.
- No automatic execution on project restore.
- No second Feed.
- No allowlist expansion for remote relay spawn.
- GPL notices stay. New files in this repo are GPL-3.0-or-later. The
  Studio archive was read: no `LICENSE` file and no `license` field. Do
  not vendor Studio into this tree.

## Risks

| Risk | Why it is real |
| --- | --- |
| Upstream velocity | 4,867 commits in 30 days. Hot files listed above |
| Closed pane switch | Every new panel is a cross-file compile break if one site is missed |
| Provider gaps | Most installed agents do not block an in-flight tool. A workflow gate does not fill that gap |
| Codex | Hook path is telemetry. Teams path is a different mechanism and not fully re-verified |
| Studio license | No LICENSE file and no package.json license field. The files do not show that the user owns every contribution. Stage 2 waits on the user and counsel |
| Second database | Not recommended. Studio's libSQL file already stores projects, workflows, teams, tasks, and worktrees |
| Session safety | Stuffing resume commands into the new database would bypass `SessionSnapshotImportTrust` |
| `events.stream` discovery | Implemented, omitted from `system.capabilities` |
| Socket default | A companion design that forgets `cmuxOnly` works in development and fails for users |
| Linux CI cannot build the app | macOS `xcodebuild` is still unrun. Phase 1's first Mac run is the real compile gate |
| License | BUSL trees and AGPL Tellurion are easy to paste. Both are out of bounds |
| `workers/fleet-artifacts` | No LICENSE file in the directory. Root `LICENSE:21-22` is the notice that applies. Do not vendor it |
| Name collision | `CMUXProjectModel` and `PanelType.project` already exist for the Xcode pane |

## What approval needs to say

Approval has to name these:

1. Stage 1 supervises the user's Studio checkout with plain Node. No second
   database. No Electron window. No Studio sources in this repo.
2. The React UI is a `WKWebView` on that server's loopback origin. It is
   not rewritten in SwiftUI, and it is not a `BrowserPanel`.
3. Stage 2, bundling Studio, waits on the user and counsel. The archive
   does not contain a grant, and it does not establish ownership of every
   contribution. Whether a bundle is a combined work is their decision.
4. Workflow-level gates are allowed for providers that cannot block an
   in-flight tool, with that limitation visible on the capability matrix.
   Studio's own `approval` step is that kind of gate. Codex hook mode in
   cmux stays non-blocking for in-flight tools.
