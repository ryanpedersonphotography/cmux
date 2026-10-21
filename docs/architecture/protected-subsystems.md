# Protected subsystems

These are cmux facilities AgentFlow must keep. The list matches the
operating rule in the master plan: do not rewrite the terminal, the window
manager, the hook installer, or the session format. Evidence is the code
that already owns each one.

## Do not replace

| Subsystem | Owner | Why it stays |
| --- | --- | --- |
| Ghostty terminal | Submodule `ef4f1570d`, `Packages/Shared/CmuxGhosttyKit`, `Packages/macOS/CmuxTerminal` | The renderer, the C ABI, and the xcframework checksum are a separate fork with its own MIT license and its own release pipeline. A patch belongs in `manaflow-ai/ghostty` only when a human maintains that fork. This work does not |
| App shell | `Sources/AppDelegate.swift`, `Sources/cmuxApp.swift` | Window registration, menus, and restore entry points. `MainWindowContext` (`AppDelegate.swift:634`) is the per-window root |
| Windows and workspaces | `TabManager` (`Sources/TabManager.swift:184`), `WorkspacesModel` | One window, many workspaces. AgentFlow projects must point at these ids, not invent a second list |
| Panes and splits | `vendor/bonsplit`, `CmuxPanes`, `Workspace.bonsplitController` | Split geometry is Bonsplit. `PaneTreeModel` maps pane tabs to `Panel` instances. Do not add a layout engine |
| Sidebar | `WorkspaceSidebarMetadataModel` in `Sources/Workspace.swift`, `CmuxExtensionKit` | Status, git, and extension sidebars already have owners |
| Browser | `BrowserPanel`, `CmuxBrowser` | Profiles, allowlists, navigation policy, and `BrowserAvailabilitySettings`. New app UI does not go through this type. See the web-panel decision |
| CLI and socket | `CLI/`, `CmuxControlSocket`, `TerminalController` v2 switches | External tools already speak this protocol. New methods, if any, are additions plus relay-policy review |
| Agent hooks | `CLI/CMUXCLI+AgentHookCatalog.swift`, Claude wrapper settings | Installers merge cmux-owned commands and leave other hooks in place. Do not replace the installer |
| Notifications and Feed | `Sources/Feed/FeedCoordinator.swift`, `UNUserNotificationCenter` path in that type | Blocking approvals already have a waiter registry. A second approval UI would race it |
| Session restore | `CmuxWorkspaces` session snapshot types, `SessionSnapshotImportTrust` | Layout, scrollback, and resume safety. Project state does not belong in this JSON |
| Remote terminals | `CmuxRemoteWorkspace`, `RemoteRelayCommandPolicy` | Default deny. Do not allowlist spawn or command parameters |
| Themes and shortcuts | Settings and Ghostty config import | Unrelated to project identity |
| Tests and tooling | `cmuxTests`, `scripts/verify-local.py`, `scripts/test-unit.sh`, `scripts/sync-test-wiring` | New tests follow these owners. Do not retarget CI at the upstream Ghostty repo |

## Session restore safety

These restrictions are already enforced. A project restore must not weaken
them.

- Agent-hook bindings do not auto-run when `terminal.autoResumeAgentSessions`
  is false
  (`WorkspaceSessionRestorePolicyService.swift:157-158`).
- A binding with `requiresPromptApproval` does not run unless prompting is
  allowed (same file, lines 160-164). Public CLI and socket resume commands
  stay manual until the user approves a signed prefix
  (`docs/agent-hooks.md` describes this; the policy service is the code).
- An imported session file is not a channel import.
  `SessionSnapshotImportTrust` (`Sources/SessionSnapshotImportTrust.swift:24-60`)
  refuses automatic SSH, cloud attach, workspace environment, custom agent
  registrations, tmux start commands, and recorded Claude background viewers.
  Scrollback loses OSC, DCS, and other control sequences. Browser panels keep
  only http(s) URLs and lose profile and diff-viewer provenance.
- Resume argv is rebuilt by `AgentResumeArgv.builtInKind`
  (`Packages/macOS/CMUXAgentLaunch/Sources/CMUXAgentLaunch/AgentResumeArgv.swift:480`).
  Claude resume goes through the wrapper shim so hooks still fire
  (lines 564-582). The sanitizer is what drops prompts and old session
  selectors before that argv is stored. Do not persist raw launch lines in a
  new store and exec them on launch.
- `chief.approve` and `chief.answer` are debug-only. A release build must
  not grow a socket path that answers approval cards without the Feed UI.

## Persistence that is not a project database

- `session-<bundleId>.json` is the layout snapshot. Writing project rows into
  it couples project identity to window restore and to the untrusted-import
  scrubber.
- `agent-journal-<bundle>.sqlite3` is an append-only agent event log
  (`AgentJournalLifecycleCenter+Database.swift:32-34`). Read it as a pattern
  for SQLite in this app. Do not migrate it into a project schema.
- `cmux-sync.sqlite3` is the team sync substrate. It is not local project
  authority.
- `~/.cmuxterm/events.jsonl` is a bounded audit log. Gap recovery still uses
  snapshot commands (`docs/events.md`, constants in `CmuxEventBus.swift:258-263`).
- `~/.cmuxterm/<agent>-hook-sessions.json` maps agent sessions to workspaces.
  It is the restore index for agents, not a project record.

## Ghostty and BUSL

Do not change the Ghostty submodule pin, `docs/ghostty-fork.md`, or
`scripts/ghosttykit-checksums.txt` for AgentFlow work.

Do not copy, modify, build, or design on `web/`, `workers/ci-artifacts/`,
`workers/iroh-v2/`, `workers/presence/`, `services/iroh-relay-minter/`, or
`cmux-tui/relays/cloudflare-do/`. Their `LICENSE` files are BUSL-1.1.

## What a later phase may add

Additive only, after the architecture in
[target-architecture.md](target-architecture.md) is approved:

- A new Swift package whose sources do not import AppKit, SwiftUI, Ghostty,
  or WebKit.
- A new `PanelType` case and one branch in `PanelContentView`, plus the
  creation function on `Workspace`, if a panel must sit beside a terminal.
- A subscription to the existing event bus and Feed store. Not a second bus.
