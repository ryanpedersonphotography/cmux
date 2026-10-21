# Target architecture

**Status: proposal, awaiting approval.** Phase 1 does not start until this
file is accepted. Nothing here is implemented.

Audited baseline: `72a39c338ef6e4d37e9ab29892f6561df1527781`.

## Decision

Put the project domain in a new Swift package inside this GPL tree. The
cmux process owns it. A thin panel adapter draws it. Do not add a companion
app, a local daemon, or a second database engine.

The package imports Foundation (and SQLite3, which the agent journal already
uses). It does not import AppKit, SwiftUI, Ghostty, WebKit, or
`CmuxControlSocket`. Tests call it with `swift test` and temporary files.

cmux remains the authority for windows, workspaces, panes, terminals, and
Feed. The new package is the authority for project identity, plans, and
workflow state. A workspace id is a reference, not the project.

## Why not a companion app

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

A later split is still possible: the package has no UI, so a process could
host it later if project state must outlive the app. This audit does not
show that need. Section 45 of the plan says not to add a service until the
audit does.

## Why not "all of it in Workspace.swift"

`Workspace.swift` is already enormous and had 159 commits on `main` in 30
days. `CLI/cmux.swift` had 221 and `TerminalController.swift` had 128.
Project rules in those files would conflict continuously and could not be
tested without the app.

The panel adapter is the only required edit to those hot files: one
`PanelType` case, one view branch, one creation method that constructs the
package's types. Workflow transitions stay in the package.

## Persistence

Use a new SQLite file under Application Support, separate from:

- `session-<bundleId>.json` (layout; untrusted imports scrub commands,
  `SessionSnapshotImportTrust.swift:24-60`)
- `agent-journal-<bundle>.sqlite3` (agent events,
  `AgentJournalLifecycleCenter+Database.swift:32-34`)
- `cmux-sync.sqlite3` (team sync)

Follow the journal's pattern: a small package, raw `sqlite3`, migrations,
tests on a temp file. Do not migrate the journal's schema. Do not store
resume commands that the session layer would auto-exec. Restoring a project
shows pending work. It does not launch agents.

## Embedded UI

No-go on `BrowserPanel` for new React panels. See
[integration-points.md](integration-points.md#embedded-web-panels).

First panels should be SwiftUI, the same way todo and notifications panes
already are. React is justified only when a surface is genuinely a document
(a diff, a canvas). If that happens, copy
`AgentSessionWebRendererCoordinator`: bundled `loadFileURL`, one bridge,
cancel other navigations, its own `PanelType`. Do not share the browser
profile's cookie store.

## Provider gates

Build workflow policy on capabilities the matrix shows, not on the Feed
docs table.

- Claude Code can block in Feed on permission, plan, and question events.
- Gemini and Kiro can block on side-effecting tool hooks.
- OpenCode can block through its plugin.
- Codex hook mode cannot. Codex Teams is a separate app-server bridge and
  stays unverified until Phase 5 reads that reply path.
- Grok, Copilot, CodeBuddy, Factory, Qoder, Kimi, Pi, and the lifecycle-only
  agents cannot block in Feed. A recipe that needs a human gate must use a
  provider that can block, or stop in the workflow package and wait for a
  cmux UI action, without pretending the agent's hook is waiting.

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

- No Rust daemon, Node server, second terminal, or plugin runtime.
- No edits under BUSL paths.
- No Ghostty pin movement.
- No automatic execution on project restore.
- No second Feed.
- No allowlist expansion for remote relay spawn.
- GPL notices stay. New files in this repo are GPL-3.0-or-later.

## Risks

| Risk | Why it is real |
| --- | --- |
| Upstream velocity | 4,867 commits in 30 days. Hot files listed above |
| Closed pane switch | Every new panel is a cross-file compile break if one site is missed |
| Provider gaps | Most installed agents do not block. A recipe that assumes they do will skip the human gate |
| Codex | Hook path is telemetry. Teams path is a different mechanism and not fully re-verified |
| Session safety | Stuffing resume commands into the new database would bypass `SessionSnapshotImportTrust` |
| `events.stream` discovery | Implemented, omitted from `system.capabilities` |
| Socket default | A companion design that forgets `cmuxOnly` works in development and fails for users |
| Linux CI cannot build the app | macOS `xcodebuild` is still unrun. Phase 1's first Mac run is the real compile gate |
| License | BUSL trees and AGPL Tellurion are easy to paste. Both are out of bounds |
| `workers/fleet-artifacts` | License file missing. Do not vendor it while that is unresolved |
| Name collision | `CMUXProjectModel` and `PanelType.project` already exist for the Xcode pane |

## What approval needs to say

Approve or reject these three points:

1. Domain package in-process, new SQLite file, no companion daemon.
2. First UI is a SwiftUI `PanelType`, not a browser surface and not React.
3. Workflow gates use only providers whose blocking behavior is in the
   matrix, with Codex hook mode treated as non-blocking.
