# React panel hosting

**Status: revised go/no-go for a dedicated web panel. Not an implementation,
and not approval to start Phase 1.**

Audited cmux baseline: `72a39c338ef6e4d37e9ab29892f6561df1527781`.
Studio snapshot: archive of `35a0d1af631a53958883e61c1b98ab072195b11c`.
See [adr-0001-orchestration-backend.md](adr-0001-orchestration-backend.md).

## Verdict

**No-go for `BrowserPanel`.** That conclusion from
[integration-points.md](integration-points.md#embedded-web-panels) stands.
A project UI that is a browser pane is tied to `BrowserProfileStore`, the
address-bar chrome, and `BrowserAvailabilitySettings`, which can close
browser panes.

**Go for a new `PanelType` whose `WKWebView` loads Studio's loopback
origin.** The condition that was open in the previous draft is met.
Studio's product UI is a Next.js server, not a static bundle. `loadFileURL`
and a custom scheme do not serve it. Several panels can be on screen
together: each is its own web view, each loads a path on the one server.
A SwiftUI rewrite of this UI is out of scope.

Keep the agent-session lockdown for navigation and messages, and add the
termination reload from `MarkdownWebRenderer`. The document URL is
`http://127.0.0.1:<port>/...`, not a file URL.

## What Studio's UI contains

Snapshot `35a0d1af631a53958883e61c1b98ab072195b11c` (archive, no `.git`).
The product UI is `apps/web`: Next.js 16 App Router, React 19. The router
is the `app/` directory. There is no client-side router beside it.

Pages under `apps/web/app/(app)/`:

| Path | What it is |
| --- | --- |
| `/` | New chat, plus a bot side panel (`app/(app)/page.tsx`) |
| `/chat/[id]` | An existing conversation |
| `/agents`, `/teams`, `/rooms` | Registries and detail pages |
| `/workflows`, `/workflows/[id]`, runs under that | Workflow editor and run views |
| `/projects`, `/projects/[slug]/...` | Project shell. Slice pages live in `apps/web/features/projects/slices/` |
| `/routines`, `/connections`, `/skills`, `/plugins` | Schedules, MCP connections, skills, plugins |
| `/imagine`, `/harnesses`, `/models` | Media, coding harnesses, model settings |
| `/settings`, `/appearance` | Settings |
| `/onboarding` | First-run setup (`app/onboarding/page.tsx`) |

The five surfaces named in the addendum, checked in this tree:

| Asked | Present |
| --- | --- |
| Kanban | No package by that name. The task slice is a column board: `apps/web/features/projects/slices/tasks/task-board.tsx`, columns from `board.ts` |
| Gantt | Not present. Milestones are a plan outline (`slices/milestones/page.tsx`, `PlanView`), not a chart |
| React Flow | Yes. `@xyflow/react` in `apps/web/package.json`. Canvas: `features/workflows/components/flow-canvas.tsx` |
| Tiptap | Not present. Notes are a textarea with a Streamdown preview (`slices/notes/editor.tsx`, `MarkdownNoteEditor`) |
| Agent dashboard | No route by that name. `/` is chat plus `BotPanelSlot`. Teams have `/teams` and `/teams/[id]` |

Build output:

- `next dev` / `next build` / `next start` use `.next`. `output: "standalone"`
  is set only when `GROKBOT_STANDALONE=1` (`apps/web/next.config.ts`). That
  is the server the Mac app bundles. There is no `output: "export"`.
- Electron's own UI is a separate Vite renderer
  (`apps/desktop/src/renderer`): Booting, FirstRun, Recovery, DevWaiting.
  `electron-vite` writes `apps/desktop/out/`. The packaged page is
  `afstudio-shell://shell/index.html` (`shell-protocol.ts`, `guards.ts`).
  After `/api/health`, the window leaves that scheme and loads the Next
  origin (`apps/desktop/src/main/index.ts` `allWindowsToApp`).

`loadFileURL` cannot host this UI. Pages are server components, and the
API routes (`/api/mcp`, workflow webhooks, health) live in the same
process. The shell scheme cannot host it either: that handler only reads
files out of the desktop renderer directory. cmux should draw boot and
crash states itself and load the Next origin for every product view.

A dedicated data store for this panel type should not be the browser
profile and should not be `WKWebsiteDataStore.default()`. Stage 1 installs
a per-launch capability. The web view receives it as an HttpOnly cookie
written into that store before `load`, which is how navigation, `fetch`,
`EventSource`, and server actions present it. A non-persistent store keeps
the cookie off disk. Electron's `installSession`
(`apps/desktop/src/main/session.ts:16-24`) adds `x-grokbot-desktop` on
every request; WKWebView has no equivalent header hook, so a header on the
first `URLRequest` is not the design. The choice between a Studio cookie
check and a native proxy is open in
[stage-1-plan.md](stage-1-plan.md#open-decision-how-the-capability-is-checked).

## What already exists

`AgentSessionWebRendererCoordinator` (`Sources/Panels/AgentSessionWebRendererCoordinator.swift`):

- One web view per coordinator, created in `ensureWebView` (line 100).
- `loadFileURL` of a bundle HTML file (line 153), with read access to
  `Bundle.main.resourceURL`.
- One `WKScriptMessageHandlerWithReply`, registered in the page world under
  `AgentSessionBridgeContract.handlerName` (lines 108-112).
- `isTrustedBridgeFrame` requires the main frame and an exact match to the
  normalized file URL (lines 370-375, 386-398). Any other message gets
  `ok: false` and is dropped (lines 201-203).
- Main-frame navigations other than that shell URL, or an in-page fragment,
  are cancelled (lines 250-286). `createWebViewWith` returns `nil` and hands
  the URL to the external-link path (lines 288-298).
- The configuration does not set `websiteDataStore` or a process pool
  (lines 106-113). WebKit's default persistent store applies.
- The type does not implement `webViewWebContentProcessDidTerminate`.

`MarkdownWebRenderer.Coordinator` does implement that callback
(`Sources/Panels/MarkdownWebRenderer.swift:797-812`). It reloads the shell
up to a fixed attempt count. The same file notes that WebKit can reclaim
the WebContent process while the view is detached from a window
(lines 815-819).

The diff viewer uses a custom scheme, `cmux-diff-viewer`, with a token in
the host and an in-memory allowlist of files
(`Sources/Panels/CmuxDiffViewerURLSchemeHandler.swift:10-13`, `register` at
line 54). Browser panes are a different host: profile data store, gestures,
and the browser navigation delegate, which forwards termination at
`Sources/Panels/BrowserNavigationDelegate.swift:292`.

`webviews/src/main.tsx` mounts the agent-session page or the diff page.
Another screen is a new mount plus a native host, not a browser setting.

## Several views at once

Studio already mounts its screens as Next routes on one origin. A cmux
panel that should show the task board loads `/projects/<slug>/tasks` (the
slice path the project shell uses). A panel that should show the workflow
canvas loads `/workflows/<id>`. Each panel is one `WKWebView`, the same
shape as `ensureWebView`. They share the Node server. They do not share a
web-content crash: termination is per web view.

Putting every route in one web view is also possible, by navigating that
view. Use separate panels when the user splits or restores them
independently. Gantt and Tiptap are not in the tree, so there is nothing
to mount for those two names.

## How the web view gets its document

| Loader | Where it exists | Fit for Studio |
| --- | --- | --- |
| `loadFileURL` | Agent session, line 153 | Not for this UI. There is no static export. |
| Custom scheme | cmux `cmux-diff-viewer://`. Studio `afstudio-shell://shell` | Studio's scheme serves the four boot screens only. Do not point a product panel at it. |
| Localhost | Studio's Next server, `127.0.0.1` | This is the loader. Allow exactly one origin (scheme, host, port) and cancel every other main-frame load. Trust script messages only from that origin's main frame. |

Arbitrary navigation stays cancelled, including `target=_blank`. The host
returns `nil` from `createWebViewWith`. Links that should leave the panel
go through the same external-link handoff the agent session uses, or they
are ignored.

The capability must not appear in a URL the event log or the back-forward
list would retain. Loopback origin checks
(`apps/web/lib/server/request-guard.ts:215-243`) still apply, and they do
not replace the capability: with no token installed,
`desktopTokenProblem` allows the request (`:86-87`).

## Native and JS messages

Use `WKScriptMessageHandlerWithReply` in the page world, one handler name
owned by this panel type. Before handling a body:

1. The frame is the main frame.
2. The frame URL equals the trusted shell URL (file or custom scheme), or
   the single localhost origin when that loader is the one in use.
3. The panel is still the live coordinator (`isClosed` is false on the
   agent-session type; a new host needs the same guard).

Fail closed with an error reply. Do not evaluate script that concatenates
untrusted strings into Swift values without a typed decoder. The agent
session parses `AgentSessionBridgeRequest` and replies `{ok, value}` or
`{ok: false, error}`. Follow that shape.

Do not install the handler on `WKWebsiteDataStore.default()` content that
also loads the system browser profile. Set `websiteDataStore` to
`WKWebsiteDataStore.nonPersistent()`, or to a store created for this panel
type, before the first load. The agent-session configuration omits this;
copying that omission would share the default store across panels and with
any other web view that uses the default store.

## Lifecycle

| Event | Required behavior |
| --- | --- |
| Suspend / leave the window | Expect WebKit to reclaim the WebContent process, as the markdown host documents at `MarkdownWebRenderer.swift:815-819`. On re-entry, reload if the shell is gone. Keep the panel id. |
| Reload | Load the same loopback path again. Do not allocate a new panel id. |
| `webViewWebContentProcessDidTerminate` | Implement it. Markdown reloads with a bounded counter (`MarkdownWebRenderer.swift:797-812`). The agent-session coordinator does not, so a crash there stays blank until something else reloads. A new host follows markdown: count attempts, then stop and show a failed state. |
| App quit | `close()` removes the script handler and drops the web view, as `AgentSessionWebRendererCoordinator.close` does at lines 173-194. |

## Panel identity across restore

A pane's identity in the session file is `SessionPanelSnapshot.id` plus
`type: PanelType` (`Sources/SessionPersistence.swift:1757-1760`). Optional
payload fields sit beside it (lines 1780-1792). Unknown `PanelType` raw
values throw (`Sources/Panels/Panel.swift:82-85`), so a build that does not
know the new case cannot decode a snapshot that contains it.

The agent-session payload is only `rendererKind`, `providerID`, and
`workingDirectory` (`Sources/SessionAgentSessionPanelSnapshot.swift`). It
does not store a document URL. A Studio panel needs its own optional
payload: the view kind (Kanban, Gantt, and the others), and the project id
the view binds to. The web view is recreated from that payload. The UUID
on the snapshot is the persistent id.

`SurfaceKind` can be constructed from any string (`SurfaceKind.swift:14-16`).
Persistence still wants a frozen static member next to the existing ones
(lines 18-53), or the tab's kind will not round-trip through the code that
switches on those members. `PanelContentView.renderedPanel` is an exhaustive
`switch` (`PanelContentView.swift:55`). One new arm constructs the host.

## Process pool and memory

The agent-session configuration does not set `WKProcessPool` and does not
set a memory cap. WebKit decides whether several web views share a
WebContent process. This audit did not measure bytes per panel, and no
figure is inferred here.

What the code does establish: each panel that follows `ensureWebView` holds
its own `WKWebView`. Five split panels are five web views. A crash
notification is per web view (`webViewWebContentProcessDidTerminate`
receives that view). Isolating a Kanban crash from a Tiptap crash requires
separate web views; it does not require a process-pool API that cmux does
not set.

A non-persistent data store avoids sharing cookies between those views. It
does not by itself give each view a process.

## Registration cost

The native edits are the boundaries in
[stage-1-plan.md](stage-1-plan.md#native-boundaries-corrected). Studio's
Next UI stays in Studio. `webviews/` is the existing Vite tree for
agent-session and diff; stage 1 does not mount the product UI there.
