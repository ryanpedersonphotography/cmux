# Current state

Phase 0 audit of `ryanpedersonphotography/cmux`, which matches upstream
`manaflow-ai/cmux` at `72a39c338ef6e4d37e9ab29892f6561df1527781`
(2026-10-20). This file records what the code does. Later files record
what not to rewrite, where to extend, how upstream moves, and a proposal
that still needs approval.

No macOS build or GhosttyKit build was run. This environment is Linux and
has no Swift toolchain, Zig, or `xcodebuild`. The Ghostty submodule is not
checked out. Claims about Zig and the Ghostty license were checked by
reading the pinned commit on GitHub, not by building it.

## Modules

The macOS app is an Xcode target (`cmux.xcodeproj`, scheme `cmux`) whose
sources live in `Sources/` (2,769 Swift files). `Workspace.swift` alone
starts at line 2757 and continues for roughly sixteen thousand lines.
Feature code is split into Swift packages under `Packages/macOS`,
`Packages/Shared`, and `Packages/iOS`, grouped by `cmux.xcworkspace`.
The CLI is `CLI/`. Tests are `cmuxTests/` (1,307 files), `cmuxCLITests/`
(41), `cmuxUITests/` (70), `Packages/*/Tests` (2,661), `tests/` (480
Python, 97 shell), and `tests_v2/` (146).

| Area | Where it lives | What it owns |
| --- | --- | --- |
| App shell | `Sources/AppDelegate.swift`, `Sources/cmuxApp.swift` | Windows, menus, session restore entry |
| Window | `AppDelegate.MainWindowContext` (`Sources/AppDelegate.swift:634`) | One `TabManager`, sidebar state |
| Workspace tabs | `Sources/TabManager.swift:184`, `WorkspacesModel` in `Packages/macOS/CmuxWorkspaces` | Ordered workspaces in one window |
| Workspace | `Sources/Workspace.swift:2755` | One Bonsplit tree, panel instances, sidebar metadata |
| Pane tree | `Packages/macOS/CmuxPanes`, `vendor/bonsplit` (MIT, pin `d67d1b114fd20edba7a19f76cc39e35bde43c2d8`) | Split geometry and the panel-id map. Bonsplit is not checked out here |
| Surfaces as resources | `Packages/macOS/CmuxSurfaceCatalogModel` | Terminal, VNC display, browser identity |
| Terminal engine | `Packages/macOS/CmuxTerminal`, `Packages/Shared/CmuxGhosttyKit` | Ghostty surfaces |
| Browser | `Packages/macOS/CmuxBrowser`, `Sources/Panels/BrowserPanel.swift` | Full browser panes |
| Socket | `Packages/macOS/CmuxControlSocket`, `Sources/TerminalController.swift` | v2 JSON-RPC |
| Extensions | `Packages/macOS/CmuxExtensionKit` | Sidebar ExtensionKit, not pane types |
| Xcode project pane | `Packages/macOS/CMUXProjectModel` | Parsed `pbxproj` for the existing project pane. Not a workbench project model |
| Agent journal | `Packages/macOS/CmuxAgentJournal` | Append-only SQLite of agent events |
| iOS | `ios/`, `Packages/iOS/*` | Separate app. Out of scope for this workbench |
| CLI | `CLI/cmux.swift` and `CLI/CMUXCLI+*.swift` | Socket client, hook installers |

Server directories exist and are Business Source licensed. See
[upstream-compatibility.md](upstream-compatibility.md). This audit did not
read them to design against them.

`CMUXProjectModel` (`Packages/macOS/CMUXProjectModel/Sources/CMUXProjectModel/ProjectModel.swift`)
is a snapshot of an Xcode project for the in-app project pane. It is not a
project-lifecycle store.

## Ghostty

Submodule pin, from `git ls-tree HEAD ghostty`:

`ef4f1570d62117ebc51e3b0f07ad4f34032267b6`

`.gitmodules` points at `https://github.com/manaflow-ai/ghostty.git`, branch
`main`. The checkout does not contain `ghostty/build.zig.zon` until
`./scripts/setup.sh` initializes the submodule.

Required Zig, from that commit's `build.zig.zon`:

`minimum_zig_version = "0.16.0"`

`scripts/ghostty-zig-version.sh` accepts that version or a newer patch in
0.16. Running it in this tree exits 1: `Ghostty Zig manifest not found`.
Older notes in `docs/ghostty-fork.md` mention Zig 0.15.2 and 0.16.0 for
historical pins. The live requirement is 0.16.0.

Ghostty's `LICENSE` at the pin is the MIT License, copyright 2024 Mitchell
Hashimoto and Ghostty contributors.

`docs/ghostty-fork.md` is an append-only patch log. Its first section is
the live pin: screen-export temporary-directory handles, commits
`0d706c3c0` (test) and `ef4f1570d` (fix). Later sections still say "current
pin" for older SHAs (`cb1ef7091`, `a53c76d06`, `7e880f6b6`, and others).
Those phrases are history. The submodule SHA is the pin.

The log's patch headings, newest first, are the fork delta. They are not
re-verified by building Ghostty here:

1. Screen export closes retained temporary-directory handles (live pin)
2. Minimum contrast uses the host-painted background
3. CSI 996 reports the surface's runtime color scheme
4. Link filter: the embedder vetoes hover regex links
5. OSC 7501 program status protocol
6. CJK fallback avoids repeated font collection scans
7. CJK punctuation keeps the resolver's font
8. Layer display after teardown no longer reaches the freed renderer
9. VT replay blank cells keep the default style
10. Cloud VT replay keeps the active viewport anchored
11. Startup input keeps its bytes
12. Unfocused surface frame pacing
13. CJK fallback ideograph sizing
14. Cloud restore replay trailing rows
15. Base feature pin
16. Fish SSH feature gating
17. Incremental embedded configuration propagation
18. Repeated word-selection drag anchor
19. iOS tokened render disposition and nonblocking prompt reveal
20. VT formatter cursor restoration after margins
21. Hangul shaping uses the resolved spelling
22. Hangul NFC/NFD canonical font resolution
23. VT stream-boundary visibility
24. Cached macOS unified loggers
25. iOS startup locale before crash reporting
26. Empty opener stderr diagnostics
27. Atomic bracketed paste delivery
28. Initial cmux theme-picker render
29. Semantic prompt row lifecycle
30. Hidden macOS renderer reclamation
31. Resolved font-binding action callbacks
32. Ordered writes survive transient backpressure
33. `os/open` stderr drain spin and zombie leak
34. Inherited from `af4dfb43f`
35. Bounded app mailbox turns
36. PTY reader and child lifecycle teardown
37. Bounded renderer mailbox turns and continuation recovery
38. External redraw delivery and surface lifetime
39. Synchronous embedder teardown and host-owned userdata
40. Transactional menu-owned key bindings and paired releases
41. Nonblocking renderer lifecycle state
42. External frontend rendering and recovery
43. Serial frame-lease rotation
44. Cursor visual and replay continuity state
45. Dynamic colors follow mutable defaults
46. Unindented hard-newline link continuations
47. Bounded Kitty graphics state
48. Indented hard-newline link continuations
49. Tokened renderer presentation callbacks
50. Authoritative sprite-font shaping runs
51. URL matching across semantic soft wraps
52. Embedded Ghostty CLI path ownership
53. Notification replay viewport authority
54. Upstream TLDR (`d560c645..7e02af879`)
55. Fork integration and conflict notes
56. Numbered embedder patches 0a and 0 through 16 (OSC color queries, render grid, display link, resize, OSC 99, theme picker, mode 2031, copy mode, `macos-background-from-layer`, kitty graphics, config-load C API, embedded IO, preedit row, URL regex, Cmd-click, surface registry, OSC 133 prompt lines, click-to-move, zsh redraw, initial focus)

GhosttyKit is not built on Linux. `scripts/ensure-ghosttykit.sh` hashes the
submodule, looks up `scripts/ghosttykit-checksums.txt`, and downloads a
prebuilt xcframework whose SHA-256 is pinned. The live row is:

`ef4f1570d62117ebc51e3b0f07ad4f34032267b6 ae38ade4e1c7e4d6ce21b8d7c16e9a95c346005848b4e2daa2afb6f56084c024`

(`scripts/ghosttykit-checksums.txt:155`). The URL shape is
`https://github.com/manaflow-ai/ghostty/releases/download/xcframework-<sha>-<flavor>/GhosttyKit.xcframework.tar.gz`
(`scripts/ensure-ghosttykit.sh:192`). The flavor is
`crashsubdir-cmux-crash-sentry-off-noi18n-v2` unless
`CMUX_GHOSTTYKIT_CRASH_REPORT_SUBDIR` overrides it (`ensure-ghosttykit.sh:76-80`).
A dirty submodule or a missing pin falls through to a local build.

The macOS build, from `.github/workflows/build-ghosttykit.yml:228`, is:

```bash
cd ghostty && zig build \
  -Dcrash-report-subdir="$GHOSTTYKIT_CRASH_REPORT_SUBDIR" \
  -Dsentry=false -Di18n=false \
  -Demit-xcframework=true -Demit-macos-app=false \
  -Dxcframework-target=universal -Doptimize=ReleaseFast
```

That workflow is `workflow_dispatch` only. Do not retarget it at
`manaflow-ai/ghostty` or upload a release from this fork.

## Windows, workspaces, panes

A window holds a `TabManager` (`Sources/AppDelegate.swift:634-636`).
`TabManager` holds `WorkspacesModel<Workspace>` (`Sources/TabManager.swift:218`).

A workspace is one sidebar tab and one `BonsplitController`
(`Sources/Workspace.swift:2755-2757`). `PaneTreeModel` owns the panel
registry and layout bookkeeping; Bonsplit owns the split tree
(`Packages/macOS/CmuxPanes/Sources/CmuxPanes/Model/PaneTreeModel.swift:5-9`).
Each pane can hold tabs. Each tab maps to a `Panel`.

Two different "surface" words are in use:

- `SurfaceResourceKind` is closed: `terminal`, `display`, `browser`
  (`Packages/macOS/CmuxSurfaceCatalogModel/Sources/CmuxSurfaceCatalogModel/SurfaceCatalogModel.swift:10-15`).
  Unknown wire values fail to decode (lines 27-34). `screen` is accepted as
  an alias of `display` (lines 19-24).
- `PanelType` is what a pane actually shows. It is also closed
  (`Sources/Panels/Panel.swift:7-26`): terminal, browser, markdown,
  filePreview, rightSidebarTool, customSidebar, simulator, agentSession,
  project, extensionBrowser, workspaceTodo, coderouterGuide, notifications,
  cloudVMLoading, mobilePairing, accountSignIn, cloudVPNSetup, chief.
  Unknown persisted values throw (lines 82-85).
- `SurfaceKind` is a `RawRepresentable` string
  (`Packages/macOS/CmuxWorkspaces/Sources/CmuxWorkspaces/Core/Values/SurfaceKind.swift:9-16`).
  Any string constructs, but the static members (lines 18-53) are the frozen
  wire values stored on Bonsplit tabs. A new string does nothing until a
  `Panel` subclass and a `PanelContentView` branch exist.

`PanelContentView.renderedPanel` is an exhaustive `switch panel.panelType`
(`Sources/Panels/PanelContentView.swift:55-78`). There is no default and no
plugin registry.

Socket creation is a smaller closed set. `v2PanelType(rawToken:)` accepts
terminal, browser, markdown, filepreview, rightsidebartool, simulator,
agentsession, and chief, and returns nil otherwise
(`Sources/TerminalControllerV2ParamParsingSupport.swift:189-208`).

`CmuxExtensionKit` scopes are sidebar metadata and actions such as
`createSurface` (`Packages/macOS/CmuxExtensionKit`). Those actions still
land in the existing `PanelType` machinery. `extensionBrowser` is a built-in
panel, not a third-party renderer.

**Verdict:** panes already host more than terminals. They cannot host an
additional *registered* type without a compile-time edit of `PanelType`,
`SurfaceKind`, `PanelContentView`, and the workspace creation path. Catalog
resources cannot grow a fourth kind without editing `SurfaceResourceKind`
and its switches. Details are in
[integration-points.md](integration-points.md).

## Browser and embedded web UI

A browser pane is a user-facing browser, not a neutral web view.
`BrowserPanel.makeWebView` builds a `CmuxWebView` on a profile
`WKWebsiteDataStore`, with back/forward gestures and a shared configuration
that installs the diff-viewer scheme and several script bridges
(`Sources/Panels/BrowserPanel.swift`, `makeWebView` / `configureWebViewConfiguration`).
`BrowserPanelView` draws an address bar (`Sources/Panels/BrowserPanelView.swift`).

React already ships, on a different host:

- `webviews/` is React 19 + Vite. `webviews/src/main.tsx` mounts either
  `agent-session` or `diff`. The README says the tree is structured to host
  more; the entry file has only those two branches.
- Agent session loads bundled HTML with `loadFileURL` and cancels any
  navigation that is not that shell
  (`Sources/Panels/AgentSessionWebRendererCoordinator.swift`).
- The diff viewer is opened as a browser tab via `cmux-diff-viewer://`
  (`Sources/Panels/CmuxDiffViewerURLSchemeHandler.swift`).
- Markdown uses `loadHTMLString` (`Sources/Panels/MarkdownWebRenderer.swift`).

**Go/no-go:** no-go for new embedded React panels as `BrowserPanel`
surfaces. Reasons and the host to copy are in
[integration-points.md](integration-points.md#embedded-web-panels).

## CLI, socket, events

The CLI is a separate process. `docs/cli-contract.md` describes user-visible
behavior. Dispatch in the app is not one registry:

- `ControlCommandCoordinator.handle` walks domain handlers and falls through
  (`Packages/macOS/CmuxControlSocket/Sources/CmuxControlSocket/Coordinator/ControlCommandCoordinator.swift`).
- Unmigrated methods hit a closed `switch` in `TerminalController`.
- `events.stream` is special-cased and is **absent** from
  `Sources/TerminalController+Capabilities.swift` (no match for
  `events.stream`). `docs/cli-contract.md` still describes it as advertised
  by capabilities. The stream works; discovery via `system.capabilities`
  does not list it.

Default socket mode is `cmuxOnly`
(`Packages/macOS/CmuxSettings/Sources/CmuxSettings/SocketControl/SocketControlSettings.swift:81-84`):
the peer must be in the cmux process tree or present a capability envelope.
`automation` and `password` modes exist and require the same user.
`RemoteRelayCommandPolicy` denies methods that are not in its routing schema,
and denies command-bearing parameters
(`Packages/macOS/CmuxRemoteWorkspace/Sources/CmuxRemoteWorkspace/Relay/RemoteRelayCommandPolicy.swift:81-88`).

Event numbers in `docs/events.md` match `Sources/CmuxEventBus.swift:258-263`:

| Contract | Code |
| --- | --- |
| Heartbeat 15s | `defaultHeartbeatIntervalSeconds = 15` |
| Replay buffer 4,096 | `defaultRetainedEventLimit = 4_096` |
| Frame cap 16 KiB | `defaultMaxEventLineBytes = 16 * 1024` |
| Subscriber queue 1,024 | `defaultMaxPendingEventsPerSubscription = 1_024` |
| Disk log 16 MiB | `defaultMaxEventLogBytes = 16 * 1024 * 1024` |
| Path | `~/.cmuxterm/events.jsonl` (`CmuxEventBus.swift:705-708`) |

`seq` and `boot_id` are process-local. A restart or a cursor older than the
buffer sets `resume.gap`. Clients are expected to snapshot after a gap.
That contract is usable by an external process that is allowed to connect.

## Persistence

Layout restore is JSON, not SQLite:

`~/Library/Application Support/cmux/session-<bundleId>.json`, plus
`-previous` and `session-history/`
(`Packages/macOS/CmuxWorkspaces/Sources/CmuxWorkspaces/Session/SessionSnapshotFileLocation.swift:6-7`).

An arbitrary imported file is untrusted. `SessionSnapshotImportTrust`
(`Sources/SessionSnapshotImportTrust.swift:24-60`) drops SSH and cloud
connections, workspace environment, custom auto-resume, tmux start
commands, and browser profile state. It rebuilds built-in agent resumes
from kind, session id, and a local working directory. Another install's own
session file stays fully trusted.

Agent-hook auto-resume is skipped when
`terminal.autoResumeAgentSessions` is off
(`Packages/macOS/CmuxWorkspaces/Sources/CmuxWorkspaces/Session/WorkspaceSessionRestorePolicyService.swift:157-158`).
Bindings that `requiresPromptApproval` do not run unless a prompt is allowed
(lines 160-164).

SQLite that already exists:

| Store | Path | Fit for a project domain |
| --- | --- | --- |
| Agent journal | `Application Support/cmux/agent-journal-<bundle>.sqlite3` (`Sources/AgentJournalLifecycleCenter+Database.swift:32-34`) | Append-only agent events. Wrong schema. Useful as a pattern |
| Sync store | `cmux-sync.sqlite3` (`Packages/Shared/CmuxSyncStore/Sources/CmuxSyncStore/CmuxSyncStore.swift:26-39`) | Team sync substrate. Wrong owner |
| Codex `state_5.sqlite` | Under the user's Codex home | Codex's database. Do not reuse |

Session JSON should stay the layout snapshot. A project identity needs its
own store. None of the existing files is that store.

## Tests and CI

155 workflow files under `.github/workflows/`. PR CI (`ci.yml`) classifies
the diff on Linux, runs `python3 scripts/verify-local.py`, then calls macOS
reusable workflows (`ci-macos.yml`, `test-macos-suite.yml`). GhosttyKit
builds only on `workflow_dispatch` (`build-ghosttykit.yml`). Web, iroh,
presence, and relay workflows exist; they were not opened.

Linux results are in `reports/phase-0/baseline-results.json`. macOS commands
are listed there as `not_run`.

## Docs that disagree with code

| Claim | Code |
| --- | --- |
| `events.stream` is in the capabilities list (`docs/cli-contract.md`) | Not present in `TerminalController+Capabilities.swift` |
| Feed waits 120 seconds (`docs/feed.md`) | Client wait is 115 seconds: `feedHookDecisionWaitSeconds = 120 - 2 - 3` (`CLI/CMUXCLI+AgentHookDefinitions.swift:8-10`). OpenCode's plugin uses 120 (`Resources/opencode-plugin.js:12`) |
| "Feed is advisory, not blocking" (`docs/feed.md`) | `FeedCoordinator` parks a semaphore for permission, plan, and question events (`Sources/Feed/FeedCoordinator.swift:703-709`). Timeout then returns no decision. It blocks until the deadline |
| Grok, Copilot, CodeBuddy, Factory, Qoder, and Kimi PreToolUse are Feed approval triggers (`docs/feed.md`) | Those hooks are installed, but only `claude`, `codex`, `hermes-agent`, `gemini`, and `kiro` are in `feedEventSemanticRegistry`. Others use `telemetryOnlyFeedEventSemantics`, which cannot block (`CLI/FeedEventClassifier.swift:261-380`) |
| Cursor `beforeShellExecution` is a Feed trigger | Cursor has no `feedHookEvents`. `beforeShellExecution` calls `shell-exec` and may ask Cursor's own prompt (`CLI/CMUXCLI+AgentHookCatalog.swift:88-108`, `CLI/AgentHookNotificationPolicy.swift:325-342`) |
| Lower sections of `docs/ghostty-fork.md` call older SHAs the current pin | Submodule pin is `ef4f1570d` |
| `webviews/README.md` is ready for more surfaces | `webviews/src/main.tsx` branches on two kinds |
| `CMUXProjectModel` sounds like a product project model | It parses an Xcode project |
