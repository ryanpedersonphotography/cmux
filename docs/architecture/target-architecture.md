# Target architecture

**Status: proposal, awaiting approval.** Phase 0 is an audit. This file is
not an approved implementation architecture. Phase 1 does not start until
this file is accepted. Nothing here is implemented.

Audited baseline: `72a39c338ef6e4d37e9ab29892f6561df1527781`.

The orchestration choice is withheld. See
[adr-0001-orchestration-backend.md](adr-0001-orchestration-backend.md).
The plan that follows a decision is
[phase-1-plan-revised.md](phase-1-plan-revised.md). It is a plan only.

## Decision

No backend is selected.

The earlier text of this file recommended an in-process Swift package and a
new SQLite file as the project authority. That recommendation is withdrawn
as the default. The addendum allows a second authoritative project database
only when reusing AgentFlow Studio's persistence is impractical. Studio was
not readable, so that impracticality was not shown, and Studio's backend was
not shown to run without Electron either.

What still holds:

- cmux remains the authority for windows, workspaces, panes, terminals, and
  Feed.
- A workspace id is a reference. It is not, by itself, the project id.
- Domain rules stay out of `Workspace.swift`, `TerminalController.swift`, and
  `CLI/cmux.swift`.
- Studio's React UI stays in React. This proposal does not rewrite it in
  SwiftUI. Hosting is
  [react-panel-hosting.md](react-panel-hosting.md): conditional go for a
  dedicated `WKWebView` panel, no-go for `BrowserPanel`.
- Native edits, once a backend is chosen, are the five boundaries in the
  revised Phase 1 plan.

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

A separate window is still a second window manager. A supervised Studio
process with no window of its own is a different proposal (ADR 0001, option
B). It is not selected. Section 45 of the original plan said not to add a
service until the audit showed the need. This addendum asks the audit to
consider Studio's backend specifically. The audit could not read it.

## Why not "all of it in Workspace.swift"

`Workspace.swift` is already enormous and had 159 commits on `main` in 30
days. `CLI/cmux.swift` had 221 and `TerminalController.swift` had 128.
Project rules in those files would conflict continuously and could not be
tested without the app.

The panel adapter is the edit those hot files get: one `PanelType` case,
one view branch, one creation method that calls out. Workflow transitions
stay in the package the ADR selects. The five native boundaries and their
sizes are in
[phase-1-plan-revised.md](phase-1-plan-revised.md#after-a-decision-the-only-cmux-edits).

## Persistence

Do not open a second authoritative project database unless ADR 0001 is
updated to say why Studio's store cannot be that authority. That update has
not been written.

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

No-go on `BrowserPanel`. Conditional go on a new `PanelType` with its own
`WKWebView`. The full note is
[react-panel-hosting.md](react-panel-hosting.md).

The host copies `AgentSessionWebRendererCoordinator` (`loadFileURL`, one
bridge, cancel other main-frame navigations) and adds the web-content
termination reload that `MarkdownWebRenderer` already has. Do not share the
browser profile's cookie store. Set a non-persistent or dedicated
`WKWebsiteDataStore`; the agent-session configuration does not, and copying
that omission shares the default store.

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
- GPL notices stay. New files in this repo are GPL-3.0-or-later. Studio's
  license was not read; do not vendor Studio into this tree until it is.

## Risks

| Risk | Why it is real |
| --- | --- |
| Upstream velocity | 4,867 commits in 30 days. Hot files listed above |
| Closed pane switch | Every new panel is a cross-file compile break if one site is missed |
| Provider gaps | Most installed agents do not block an in-flight tool. A workflow gate does not fill that gap |
| Codex | Hook path is telemetry. Teams path is a different mechanism and not fully re-verified |
| Studio unread | Private repo `ryanpedersonphotography/agentflow-studio` returned 404 to this token. SHA `35a0d1af631a53958883e61c1b98ab072195b11c` was not verified. Backend, license, and persistence are unknown |
| Second database | Withdrawn as the default. Allowed only after Studio's store is shown to be impractical |
| Session safety | Stuffing resume commands into the new database would bypass `SessionSnapshotImportTrust` |
| `events.stream` discovery | Implemented, omitted from `system.capabilities` |
| Socket default | A companion design that forgets `cmuxOnly` works in development and fails for users |
| Linux CI cannot build the app | macOS `xcodebuild` is still unrun. Phase 1's first Mac run is the real compile gate |
| License | BUSL trees and AGPL Tellurion are easy to paste. Both are out of bounds |
| `workers/fleet-artifacts` | License file missing. Do not vendor it while that is unresolved |
| Name collision | `CMUXProjectModel` and `PanelType.project` already exist for the Xcode pane |

## What approval needs to say

The three points that used to end this file are withdrawn. Approval has to
name these instead:

1. ADR 0001 may stay withheld until Studio is readable, or the user may
   choose A or B with the missing evidence listed as accepted risk.
2. The React UI is hosted in a dedicated `WKWebView` panel. It is not
   rewritten in SwiftUI, and it is not a `BrowserPanel`.
3. Workflow-level gates are allowed for providers that cannot block an
   in-flight tool, with that limitation visible on the capability matrix.
   Codex hook mode stays non-blocking for in-flight tools.
