# Integration points

Where AgentFlow can attach, and where it cannot, at upstream
`72a39c338ef6e4d37e9ab29892f6561df1527781`.

## Pane and surface registration

There is no runtime registry of pane types.

To show a new pane beside a terminal, a change has to touch all of:

1. `PanelType` in `Sources/Panels/Panel.swift:7-26` (closed enum; unknown
   raw values throw at lines 82-85).
2. A static `SurfaceKind` in
   `Packages/macOS/CmuxWorkspaces/Sources/CmuxWorkspaces/Core/Values/SurfaceKind.swift:18-53`
   if the tab is persisted. `init(rawValue:)` accepts any string (lines 14-16)
   and that string is not enough.
3. A `Panel` subclass and a branch in
   `PanelContentView.renderedPanel`
   (`Sources/Panels/PanelContentView.swift:55`).
4. A creation method on `Workspace` (`Sources/Workspace.swift`), next to
   `newBrowserSurface` and `newAgentSessionSurface`.
5. Session encode/decode for that panel, or the pane disappears on restore.
6. Optionally `v2PanelType(rawToken:)`
   (`Sources/TerminalControllerV2ParamParsingSupport.swift:189-208`) if the
   socket should create it. Today that parser does not accept `project`,
   `notifications`, or `extensionBrowser`.

`SurfaceResourceKind` (`terminal`, `display`, `browser`) is a different
closed enum for cloud and local resource identity
(`SurfaceCatalogModel.swift:10-15`). A project panel is not a catalog
resource unless something projects it. Do not add a fourth catalog kind for
a local UI panel.

`CmuxExtensionKit` can ask the host to create or select a surface. It does
not supply a view for a new kind.

Conflict note: `Sources/Workspace.swift` had 159 commits on `main` in the
30 days before this audit, and `Sources/TerminalController.swift` had 128.
A new panel should be a small call into a new type, not new logic inside
those files. Counts are in
[upstream-compatibility.md](upstream-compatibility.md).

## Embedded web panels

**No-go.** Do not host new React panels as `BrowserPanel` / `SurfaceKind.browser`.

Reasons from code:

- Browser panes are profile-backed browsers. `makeWebView` attaches
  `BrowserProfileStore`'s `WKWebsiteDataStore`, navigation gestures, and the
  diff-viewer scheme plus page scripts
  (`Sources/Panels/BrowserPanel.swift`). `BrowserPanelView` is the address-bar
  chrome (`Sources/Panels/BrowserPanelView.swift`).
- `BrowserAvailabilitySettings` and the managed disable path close and block
  browser panes. A project UI that lives there disappears when the user
  disables the browser. Agent-session creation does not consult that setting.
- Navigation policy (`BrowserURLAllowlistPolicy`, the browser navigation
  delegate) assumes untrusted web. An app shell wants the opposite: allow
  one bundled file and cancel everything else, which is what
  `AgentSessionWebRendererCoordinator` already does.
- The diff viewer is the one React app that *does* run inside a browser
  pane, through the registered `cmux-diff-viewer://` scheme. That is a
  special case with its own allowlist, and socket `browser.open` of that URL
  fails when the browser is disabled (`Sources/TerminalController.swift`).

**What to reuse instead:**

- The `webviews/` Vite bundle and the committed output under
  `Resources/markdown-viewer/webviews-app`, if a panel needs React.
- The load pattern in `AgentSessionWebRendererCoordinator`: `loadFileURL`
  of a bundle file, one script-message handler, cancel any other navigation.
- A new `PanelType`, not `browser`.

`webviews/src/main.tsx` only mounts `agent-session` or `diff`. Adding a
third page there is a frontend change plus a new native host. It is not a
browser-surface configuration change.

Markdown's `loadHTMLString` host is the other existing minimal web view.
Use it only for static HTML, not for a React application.

## Socket and events

An external process can drive cmux when socket admission allows it.
Default mode `cmuxOnly` does not allow an unrelated process
(`SocketControlSettings.swift:81-84`). `automation` or `password` mode does,
same UID.

Once admitted, the CLI and `cmux rpc` can list windows, workspaces, panes,
and surfaces; create workspaces; split terminals; send text and keys; focus;
stream events; and push Feed items. Those methods are split across
`ControlCommandCoordinator` and the legacy switches in `TerminalController`.
`cmux capabilities` prints `system.capabilities`. `events.stream` is
implemented and omitted from that list.

The event stream is the right catch-up mechanism: monotonic `seq`, `boot_id`,
in-memory replay of 4,096 events, `resume.gap` when the cursor is stale,
16 KiB frame cap, 1,024-event subscriber queue, `slow_consumer` close, and
`~/.cmuxterm/events.jsonl` rotated at 16 MiB (`CmuxEventBus.swift:258-263`
and `705-708`). After a gap, the client refreshes with snapshot methods.
The disk log is not the source of truth across a long outage.

Remote `cmux ssh` relays stay default-deny
(`RemoteRelayCommandPolicy.swift:81-88`). A project service must not assume
those methods work on a remote host.

This is enough to orchestrate terminals from outside the process. It is not
enough to put a Kanban view in a pane. See
[target-architecture.md](target-architecture.md).

## Hook installation

`cmux hooks setup` walks `CMUXCLI.agentDefs` in
`CLI/CMUXCLI+AgentHookCatalog.swift`. Claude Code is not in that array. The
Claude wrapper writes a settings document whose `PermissionRequest` entry is
`cmux hooks feed --source claude` with timeout 125
(`CLI/CMUXCLI+ClaudeHookSettings.swift:85-89`).

For the catalog agents, install loads the existing config, removes commands
cmux owns, and reinserts them. Other hooks stay. Codex also gets a
`config.toml` trust update (`postInstallAction: .codexConfigToml`, catalog
line 27). The Codex *wrapper* can inject per-invocation hooks when the
persistent file does not already cover them; that path is separate from
`hooks setup` and is described in `docs/agent-hooks.md`. The persistent file
is what the installer edits.

OpenCode, Pi, OMP, Campfire, and Amp install plugin or extension files
rather than a JSON merge. OpenCode's Feed path is
`Resources/opencode-plugin.js`, which calls `feed.push` itself.

Hook scripts call back into `cmux hooks feed`, which classifies stdin and
sends `feed.push`.

## Feed and blocking approvals

`FeedCoordinator.isBlockingDecisionEvent` is true only for
`permissionRequest`, `exitPlanMode`, and `askUserQuestion`
(`Sources/Feed/FeedCoordinator.swift:703-709`). The waiter is a
`DispatchSemaphore` in `Sources/Feed/FeedWaiterRegistry.swift`. While the
hook is still waiting, `postNotificationIfStillAwaiting` posts a user
notification with inline actions (same coordinator, notification delivery
extension). A click sends `feed.permission.reply`, `feed.question.reply`, or
`feed.exit_plan.reply`, which signals the semaphore. On timeout the hook
prints no decision and the agent uses its own prompt.

The CLI budget is 120 seconds (`feedHookProcessTimeoutMilliseconds`,
`CLI/CMUXCLI+AgentHookDefinitions.swift:8`). The socket wait is 115 seconds
(lines 9-10). Docs that say 120 describe the hook process budget, not the
client wait.

Codex is special. Its registry entry maps `PermissionRequest` to
`nativeApprovalPrompt` and `PreToolUse` to `toolStart`
(`CLI/FeedEventClassifier.swift:276-284`), with a comment that blocking
would run before Codex's own reviewer. Codex Teams is a different path:
the app-server bridge pushes actionable cards. That path was not re-traced
line by line in this audit beyond the catalog and classifier; treat
"Codex Teams blocks in Feed" as documented behavior confirmed by the
presence of `CodexTeamsApprovalBridge.swift`, and confirm the reply path
before depending on it in Phase 5.

## Provider capability matrix

Cells are what this audit read in code. `unverified` means this pass did not
find an implementation. Sandbox means "cmux configures or records a sandbox,"
not "the provider has a sandbox feature."

Resume commands are `AgentResumeArgv.builtInKind`
(`AgentResumeArgv.swift:487-558`).

| Provider | Blocking hook | Structured tool events | Session resume | Sandbox | Approvals |
| --- | --- | --- | --- | --- | --- |
| Claude Code | Yes. `PermissionRequest` runs `hooks feed --source claude`, timeout 125 (`CMUXCLI+ClaudeHookSettings.swift:85-89`). Classifier: `approvalRequest` (`FeedEventClassifier.swift:262-263`). Waiter: `FeedCoordinator.swift:703-709` | Yes for events the classifier names (`tool_name` path is the feed bridge). PreToolUse is `toolStart`, not an approval | Wrapper `claude` plus `--resume`. Captured executable is ignored so the wrapper still injects hooks (`AgentResumeArgv.swift:564-582`) | Observes permission mode and reapplies it on user-owned resume (`AgentResumeArgv.swift:477-479`). Does not configure an OS sandbox here | Feed blocks on PermissionRequest, ExitPlanMode, and AskUserQuestion |
| Codex | Hook feed: no. `PermissionRequest` is `nativeApprovalPrompt`, `PreToolUse` is `toolStart` (`FeedEventClassifier.swift:276-284`) | Yes. Those events are installed (`AgentHookCatalog.swift:18-26`) | `codex resume <id>` plus preserved argv (`AgentResumeArgv.swift:498-510`) | unverified. Installer enables hooks in `config.toml`; it does not set a sandbox in the catalog | Hook path is telemetry plus a native permission notification. Codex Teams app-server bridge is a separate blocking Feed path (`CLI/CodexTeamsApprovalBridge.swift`); reply behavior not re-executed here |
| Grok | No. `feedHookEvents: ["PreToolUse"]` (`AgentHookCatalog.swift:46`) and Grok is absent from the semantic registry, so the telemetry table applies (`FeedEventClassifier.swift:362-364`) | Telemetry only for PreToolUse | `grok -r <id>` (`AgentResumeArgv.swift:511-512`) | unverified | Not a Feed decision |
| OpenCode | Yes, outside the classifier. Plugin `wait_timeout_seconds` is 120 for the blocking call and 0 for telemetry (`Resources/opencode-plugin.js:12`, `815`, `831`) | Yes, plugin payload | `opencode --session <id>` (`AgentResumeArgv.swift:533-536`) | unverified | Feed, via direct `feed.push` |
| Pi | No feed decision. No `feedHookEvents` in the catalog entry (`AgentHookCatalog.swift:56-61`) | Extension telemetry, not a Feed approval | `pi --session <id>` (`AgentResumeArgv.swift:513-514`) | unverified | None in the classifier |
| OMP | No | Lifecycle extension only | `omp --session <id>` (lines 515-516) | unverified | None |
| Campfire | No | Lifecycle extension only | `campfire --session <id>` (lines 517-518) | unverified | None in Feed |
| Amp | No | unverified beyond the plugin file install | `amp threads continue <id>` (lines 519-522) | unverified | None |
| Cursor CLI | Not Feed. `beforeShellExecution` is `shell-exec` with delivery `.direct` (`AgentHookCatalog.swift:97-101`). `shouldRequestCursorNativeApproval` returns true only when `sandbox` is false and local allowlist checks pass (`AgentHookNotificationPolicy.swift:336-342`) | Command payload on that hook | `cursor-agent --resume <id>` (line 523-524) | Reads the hook's `sandbox` boolean. Does not set it | Native Cursor prompt, not Feed |
| Gemini | Yes for side-effecting PreToolUse. Registered as `approvalCapableFeedEventSemantics` (`FeedEventClassifier.swift:326-328`, `346-348`) | PreToolUse is installed (`AgentHookCatalog.swift:121`) | `gemini --resume <id>` (lines 525-526) | unverified | Feed, when the tool is classified side-effecting |
| Kiro | Yes for side-effecting `preToolUse` (`toolStartMaybeApproval`, `FeedEventClassifier.swift:334-336`) | preToolUse and postToolUse installed (`AgentHookCatalog.swift:135`) | `kiro-cli chat --resume-id <id>` (lines 527-530) | unverified | Feed for side-effecting tools. Hooks apply only to the `cmux` Kiro agent (catalog post-install note, lines 136-139) |
| Antigravity | No feed events in the catalog entry (lines 141-157) | Lifecycle hooks only | `agy --conversation <id>` (lines 531-532) | unverified | None in Feed |
| Rovo Dev | No feed events (lines 159-169) | Lifecycle YAML only | `acli rovodev run --restore <id>` (lines 537-540) | unverified | None in Feed |
| Hermes | Feed path does not block. `pre_tool_call` is `toolStart`; `pre_approval_request` is `statusNotification` (`FeedEventClassifier.swift:308-318`) | Those four feed events are installed (`AgentHookCatalog.swift:189`) | `hermes --resume <id>` (lines 541-544) | unverified | Real approval is the `notification` / `approval-response` subcommands (catalog lines 182-183), not a Feed waiter |
| Copilot | No. `preToolUse` is installed (`AgentHookCatalog.swift:206`) and the telemetry table maps `preToolUse` to `toolStart` (`FeedEventClassifier.swift:366-367`) | Telemetry | `copilot --resume <id>` (lines 545-546) | unverified | Not a Feed decision |
| CodeBuddy | No. Same telemetry fallback. `feedHookEvents: ["PreToolUse"]` (line 219) | Telemetry | `codebuddy --resume <id>` (lines 547-548) | unverified | Not a Feed decision |
| Factory | No. Same (line 232) | Telemetry | `droid --resume <id>` (lines 549-550) | unverified | Not a Feed decision |
| Qoder | No. Same (line 244) | Telemetry | `qodercli --resume <id>` (lines 551-552) | unverified | Not a Feed decision |
| Kimi | No. `PreToolUse` and `PostToolUse` installed (line 263), source not in the blocking registry | Telemetry | `kimi --resume <id>` (lines 553-554) | unverified | Not a Feed decision |
| Muse | No feed events in the catalog entry (lines 265-279) | Lifecycle only | `muse resume <id>` (lines 555-558) | unverified. Hooks are pinned because Muse clears the environment (catalog comment, line 280) | None in Feed |

`docs/feed.md` lists Grok, Copilot, CodeBuddy, Factory, Qoder, and Kimi as
Feed triggers. The installer does call `cmux hooks feed` for those events.
The classifier then refuses to block. That is the disagreement that matters
for a workflow gate: those providers cannot stop a tool for a human inside
Feed today.

## Companion-app boundary

A separate app can own project records and call the socket for terminals,
focus, events, and Feed *if* the user turns socket admission on. It cannot
register a pane, read the full terminal emulator, or approve Chief cards in
a release build. Phase 2 of the plan requires a project panel beside a
terminal. That requirement is in-process. The recommendation is in
[target-architecture.md](target-architecture.md).
