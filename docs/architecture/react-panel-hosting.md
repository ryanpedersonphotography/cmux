# React panel hosting

**Status: revised go/no-go for a dedicated web panel. Not an implementation,
and not approval to start Phase 1.**

Audited cmux baseline: `72a39c338ef6e4d37e9ab29892f6561df1527781`.
AgentFlow Studio's React tree was not readable. See
[adr-0001-orchestration-backend.md](adr-0001-orchestration-backend.md).
This note says how cmux can host a bundled React view. It does not say that
Studio's screens already load this way.

## Verdict

**No-go for `BrowserPanel`.** That conclusion from
[integration-points.md](integration-points.md#embedded-web-panels) stands.
A project UI that is a browser pane is tied to `BrowserProfileStore`, the
address-bar chrome, and `BrowserAvailabilitySettings`, which can close
browser panes.

**Conditional go for a new `PanelType` whose view owns a `WKWebView`.**
The host copies `AgentSessionWebRendererCoordinator` for loading and for
the script bridge, and it copies `MarkdownWebRenderer`'s
`webViewWebContentProcessDidTerminate` reload, which the agent-session host
does not implement. Several such panels can be on screen together. Each one
is its own coordinator and its own web view.

The condition: the React assets can be served by one of the three loaders
below, and every native message comes from the trusted main frame. Studio
has not been shown to meet that condition. A SwiftUI rewrite of Studio's
UI is out of scope.

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

Kanban, Gantt, React Flow, Tiptap, and an agent dashboard can coexist as
**separate panels**. The agent-session pattern is already one web view per
panel: `ensureWebView` stores a single `WKWebView` on the coordinator, and
each panel has its own coordinator. Nothing in that type limits the count
to one panel per window.

They can also coexist as routes inside one React bundle and one web view.
That is one panel identity and one crash domain. Use it when the screens
share one document. Use separate panels when the user splits or restores
them independently. cmux does not provide a React tree that mounts those
five screens today, and Studio's tree was not checked for them.

## How the web view gets its document

| Loader | Where cmux uses it | Fit for a Studio panel |
| --- | --- | --- |
| `loadFileURL` | Agent session, line 153 | A static bundle inside the app. Trust is an exact `file://` URL. `allowingReadAccessTo` on `Bundle.main.resourceURL` lets the page read that directory. Prefer a narrower directory if the bundle can be split out. |
| Custom scheme | `cmux-diff-viewer://` plus a token allowlist | Session-scoped assets. The scheme handler serves only registered files. The bridge checks the scheme and token the way the diff viewer checks `hasActiveSession`. |
| Localhost | Not used by the agent-session host | Only if Studio's backend is actually an HTTP service on `127.0.0.1`. Unverified. The navigation policy would allow exactly one origin (host, port, and scheme) and cancel every other main-frame load. The bridge would require that same origin on the main frame. A file-URL equality check does not transfer to HTTP. |

Arbitrary navigation stays cancelled, including `target=_blank`. The host
returns `nil` from `createWebViewWith`. Links that should leave the panel
go through the same external-link handoff the agent session uses, or they
are ignored.

A localhost origin also needs the per-launch token from
[adr-0001](adr-0001-orchestration-backend.md). The token is checked on the
request. It is not placed in a URL that the event log or WebKit's
back-forward list would retain.

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
| Reload | `loadFileURL` or the scheme URL again. Re-bind the bridge. Do not allocate a new panel id. |
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

The native edits are the panel-registration row in
[phase-1-plan-revised.md](phase-1-plan-revised.md#native-integration-boundaries).
The React bundle, if it is Studio's, stays outside those files. `webviews/`
is the existing Vite tree for agent-session and diff; adding Studio's app
there is a product choice for after Studio is readable, not a change made
in this audit.
