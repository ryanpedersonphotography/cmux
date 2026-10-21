# Stage 1 plan

**Status: plan only. Not approved. Do not implement it.**

Stage 1 as previously written is withdrawn. It deferred authentication on a server that can read project data, approve actions, and start agents, and it called the work cmux-only. [review-response-codex-1.md](review-response-codex-1.md) records why. Option B stands: supervise Studio's Next.js server, keep its libSQL file, host the React UI in a `WKWebView`. This file is the work list that has to be accepted before any of it is written.

Nothing here authorizes a commit under `Sources/`, `CLI/`, packages, `.github/workflows/`, or the Studio repo. cmux baseline `72a39c338ef6e4d37e9ab29892f6561df1527781`. Studio archive `35a0d1af631a53958883e61c1b98ab072195b11c`.

## Open decision: how the capability is checked

The user has not chosen. Both options are below. The recommendation is **(a)**. Stage 1 does not start until the user picks one.

A per-launch capability has to be checked inside the process that holds the data, or Studio has to be unreachable from every other local process. `desktopTokenProblem` returns null when no token is installed (`apps/web/lib/server/request-guard.ts:86-87`). macOS has no practical per-process filter on a TCP port bound to `127.0.0.1`.

### (a) Minimal Studio auth change

Studio installs the token it already understands, before it listens. cmux delivers that token to the web view as an HttpOnly cookie on a dedicated data store.

| | |
| --- | --- |
| Studio diff | Small. A pre-listen installer calls `installDesktopToken` (`apps/desktop/src/main/desktop-token.ts:19-20`) from a pipe or fd that is closed before any child is spawned. Not `process.env`: `GROKBOT_DESKTOP_TOKEN` is denied (`env.ts:8`) and `ps` shows the environment. Not `process.parentPort`: `server-host.ts:56-58` exits when that port is missing, and plain Node has no utility-process port. `desktopTokenProblem` (`request-guard.ts:86-90`) also accepts the same value from an HttpOnly cookie. `/api/health` leaves the exemption in `isDesktopTokenExempt` (`:72-74`) or stops returning `onboarded`. |
| cmux diff | Small, in the new panel host. Before `load`, write the cookie into that web view's `WKHTTPCookieStore`. Do not put the value in the URL, the event log, or the environment. |
| Page | Covered. The navigation sends the cookie. |
| API `fetch` | Covered. Same-origin `fetch` sends the cookie. |
| SSE | Covered. `EventSource` to `/api/events` is a same-origin GET and sends the cookie. `originGuard` already wraps that route (`apps/web/app/api/events/route.ts:8`). |
| Server actions | Covered. They are same-origin POSTs; the cookie is attached with `Next-Action`. No header injection is required. |
| Approvals and mutations | Covered. They are ordinary requests to the same origin once the guard requires the capability. |
| Second local process | Denied, once the token is installed. A client without the cookie fails `desktopTokenProblem`. The acceptance test is a second process, not a forged `Origin`. |
| Upstream conflict | The Studio repo, not `Workspace.swift`. cmux conflict stays on the panel-registration sites below. |
| Security | Page JavaScript cannot read an HttpOnly cookie. Script running in the page can still send it, which is the same property as Electron adding the header on a fetch the page starts (`session.ts:16-24`). The cookie lives in the panel's data store, not the browser profile, and a non-persistent store keeps it off disk. |

### (b) Authenticated native proxy, Studio untouched

cmux terminates TLS-free HTTP on `127.0.0.1` and forwards to Studio. The web view's origin is the proxy.

| | |
| --- | --- |
| Studio diff | None, which is the constraint that fails the security condition. With no token installed, `desktopTokenProblem` allows every request. The proxy's added header is checked only after Studio installs a token. |
| cmux diff | A new streaming reverse proxy: chunked bodies, `text/event-stream` without buffering, and Next server-action posts (`Next-Action`, router state). That is a large new Swift surface and it tracks Next's protocol. |
| Page, API, SSE, server actions | Covered only for clients that use the proxy origin. SSE works if the proxy streams. Server actions work if every action header and body is forwarded. |
| Second local process | Not denied. Studio remains on its own TCP port, and the guard is open. Closing that port, or moving the listen to a socket the proxy alone can open, is a Studio listen-path change, so the "untouched" option is gone. |
| Upstream conflict | Low on `Workspace.swift`. The proxy is new code with a standing conflict against Next's request shapes. |
| Security | Fails condition 1 while Studio accepts unauthenticated loopback TCP. Hiding the port in the UI does not hide it from another process. |

**(a)** is the recommendation because it is the option that can deny a second local process and can cover SSE and server actions without reimplementing Next's protocol. **(b)** avoids a Studio diff and cannot meet the denial test unless Studio stops accepting other local clients, which is a Studio change of its own.

## Work items

Each row is one item. "Gate" is the command that proves the acceptance test. Gates that need a Mac are marked. This environment did not run them.

| ID | Owner | Files and functions | Acceptance test | Gate |
| --- | --- | --- | --- | --- |
| S1 | Studio, plus cmux for the cookie. Blocked on the open choice above | If (a): `desktopTokenProblem` and `isDesktopTokenExempt` (`apps/web/lib/server/request-guard.ts:72-90`); a pre-listen caller of `installDesktopToken` (`desktop-token.ts:19-20`); tests in `apps/web/lib/server/__tests__/request-guard.test.ts`. cmux: cookie write on the panel `WKHTTPCookieStore` before `load`. If (b): a new proxy type, and this row stays open because (b) does not deny a second process | A second local process, with no cookie and no `x-grokbot-desktop` header, receives 403 on a page GET, an API POST, `GET /api/events`, a server-action POST, an approval POST, and a mutation. The web view with the cookie receives 200 on each of those shapes. `/api/health` does not return `onboarded` to a client that lacks the capability. Forged `Host` and `Origin` do not satisfy the test | `pnpm --filter @grokbot/web exec vitest run lib/server/__tests__/request-guard.test.ts` on the Studio tree. The second-process case starts `next start` and uses two clients. Linux can run it. It was not run in Phase 0 |
| S2 | User, then Studio or cmux | The choice in the section above. No code until it is made | The plan's recommendation is (a). The written decision names (a) or (b) and the coverage table that goes with it | None. This is the approval |
| S3 | cmux | App-owned config under Application Support, read by the supervisor. Not a field on `SessionPanelSnapshot`. Not a path taken from workspace JSON | The supervisor refuses a relative path, a path supplied by a session snapshot, and a checkout it was not configured with. It does not run `pnpm install` | `swift test` of the config type on a Mac with Command Line Tools. Linux cannot compile it |
| S4 | cmux | Copy the behavior of `loginShellBaseEnv` / `loadLoginEnv` (`apps/desktop/src/main/login-env.ts:33-46`, the 10s shell in `loadLoginEnv`) and `buildServerEnv` / `isDeniedEnvName` (`env.ts:11-39`). Resolve absolute `node` and `pnpm`. Require Node `>=22.15` and pnpm `12.8.1` (`package.json:5-8`) | Default runtime is `next build` then `next start` (`apps/web/package.json:6-8`). `next dev` is a separate developer switch, not the default, and it still installs the capability. A Finder launch (bare `PATH`) finds Node through the login-shell path or fails with a named error. A sanitized env drops `NODE_OPTIONS`, `GROKBOT_DESKTOP_TOKEN`, and the `ELECTRON_` / `npm_` / `DYLD_` prefixes, and forces `HOSTNAME=127.0.0.1`, `PORT`, `GROKBOT_DATA_DIR`, and `NODE_ENV=production` for `next start`. `next start` without a matching build fails before listen | `swift test` for the env builder and version checks (Mac, Command Line Tools). A spawn test from a cleaned environment is the same suite. `next build` itself is `pnpm --filter @grokbot/web build` and was not run in Phase 0 |
| S5 | cmux and Studio | New supervisor type. States: `stopped`, `starting`, `authenticated-ready`, `backing-off`, `failed`, `stopping`. Delays from `restartDelay` (`apps/desktop/src/main/restart.ts:1-13`): 1s, 5s, 15s, then stop after 3 crashes in 2 minutes. Stdout and stderr are drained the way `login-env.ts` drains the login shell. Stop is SIGTERM to the process group, then SIGKILL. One lock file in `GROKBOT_DATA_DIR`, taken by this supervisor and by Studio Desktop (`apps/desktop/src/main/index.ts` data-dir startup). Readiness is an authenticated response, not `body.app == "grokbot"` alone (`apps/web/app/api/health/route.ts:10-13`) | A second owner of the same data directory exits without opening the database. Three crashes inside the window end in `failed` rather than a fourth spawn. A child that fills stdout does not stall the supervisor. After stop, no grandchild remains. Ready is not reported for a process that answers `/api/health` without the capability. `choosePort`'s probe/listen race (`port.ts:21-24`) is handled by retrying the next bind, not by trusting the probe | `swift test` for the state machine (Mac, Command Line Tools) if the type imports no AppKit. The lock test is a small Node fixture shared with Studio Desktop: `pnpm exec vitest run` on that fixture. Process-group kill is a Mac spawn test |
| S6 | cmux | Native starting and recovery view owned by the panel host. Do not load `afstudio-shell://`. Persist project id and route path in the panel payload, not the loopback origin. `load` runs only from `authenticated-ready`. On `webViewWebContentProcessDidTerminate`, follow `MarkdownWebRenderer.swift:797-812` (bounded reload) and also reload when the supervisor re-enters `authenticated-ready` | Restoring a layout shows the native shell while the state is `starting` or `backing-off`. The web view's URL is still empty. After authenticated ready, it loads the saved path on the current origin. A WebContent crash reloads that path until the attempt limit, then the native failed state. A server restart does not leave the old document up | The state assertion is `swift test` (Mac, Command Line Tools) on a host double that records load calls. The web-view crash path is `xcodebuild` scheme `cmux-unit` after GhosttyKit is present (full Xcode) |
| S7 | cmux | `PanelType` case only (`Panel.swift:27-33`); no new legacy decoder arm. `PanelContentView.renderedPanel` (`PanelContentView.swift:55`). `SurfaceKind` static (`SurfaceKind.swift:18-53`). Workspace encode `switch panel.panelType` (`Workspace.swift:616`) and `createPanel` (`:1621`, new arm beside `:2354`). Dock encode (`DockSplitStore+SessionSnapshot.swift`, `default` at `:442`) and dock restore (`DockSplitStore+SessionRestore.swift`, `default` at `:256`). Optional payload on `SessionPanelSnapshot` (`SessionPersistence.swift:1757-1792`). `SessionSnapshotSchema.currentVersion` stays 1 (`:17-19`) | Upgrade: a version-1 file with no Studio panel decodes. Downgrade: a fixture of today's decoder (`Panel.swift:82-85`) returns `.unusable` (`SessionSnapshotRepository.swift:69-75`); `preserveUnusableSnapshot` (`:324-333`) keeps a side copy because the version is not newer; `loadStartupSnapshot` (`:461-472`) returns the backup. Unknown type: a raw value that is not a case throws and the file is unusable. Dock: the new type round-trips; an unknown dock type returns nil from that panel only. Backup: an unusable primary with a good backup starts on the backup. A version bump to 2 is not part of this item; `preserveNewerSchemaSnapshot` (`:275-278`) only runs when the probed version is greater, and startup would still display the backup | `xcodebuild` scheme `cmux-unit` after `./scripts/ensure-ghosttykit.sh` (full Xcode). The repository tests around `SessionSnapshotRepository` are the place these cases go |
| S8 | Studio and cmux | Studio already serves `GET /api/events` (`apps/web/app/api/events/route.ts:6-18`) through `eventResponse` (`apps/web/features/events/stream.ts:26-67`), which has no replay buffer. The bridge subscribes with the capability from S1. Publishing into cmux uses the existing durable allocator (`CmuxEventSequenceStore.allocate`, `CmuxEventBus.publishDurableOnPublicationQueue`). `boot_id` stays the cmux process id (`CmuxEventBus.swift:281`). Studio event names are the payload, not a second sequence | An unauthenticated `GET /api/events` is 403. After a Studio restart, the bridge refreshes Studio state before treating the stream as live, because `eventResponse` does not replay. Events published into cmux receive `seq` from the sidecar and do not reuse or skip across a cmux restart. A cmux subscriber that presents an `after` older than the retained window gets `resume.gap` (`CmuxEventBus.swift:527-534`) and then uses snapshot methods. A Studio restart does not change `boot_id` | Studio: the vitest command in S1, plus a test that `eventResponse` emits no backlog. cmux: the existing event-bus tests under `swift test` / `cmux-unit` for seq allocation and gap reasons |
| S9 | cmux | New web-view configuration, following `AgentSessionWebRendererCoordinator` navigation policy (`:250-298`) and `isTrustedBridgeFrame` (`:370-375`). Set `websiteDataStore` to a store created for this panel (non-persistent, so the per-launch cookie is not on disk). Do not use `WKWebsiteDataStore.default()` and do not use the browser profile store. `createWebViewWith` returns nil. One script handler, main frame, exact origin | A navigation whose scheme, host, or port differs from the supervisor's origin is cancelled. `target=_blank` does not open a view. A script message from a subframe or another origin is dropped. The cookie from S1 is visible to that web view and is absent from the default store. `NSAllowsArbitraryLoadsInWebContent` (`Resources/Info.plist:236-240`) is left as it is; the test does not treat ATS as the control | Policy object: `swift test` on a Mac with Command Line Tools if it does not need a live `WKWebView`. Origin cancellation against a live web view: `cmux-unit` (full Xcode, GhosttyKit present) |
| S10 | CI, proposal only | No file is added under `.github/workflows/`. The job description in [phase-1-plan-revised.md](phase-1-plan-revised.md#ci-proposal-do-not-enable) is the text. It checks out the repo, requires Xcode 26, runs `./scripts/ensure-ghosttykit.sh` (pinned sha256) or `./scripts/download-prebuilt-ghosttykit.sh` the way `.github/workflows/ci-macos.yml:715-731` does, downloads the Metal toolchain, then `./scripts/test-unit.sh` `build-for-testing` and `test`, including the tests from S5, S7, and S9 once they exist | A clean runner fails the job when `GhosttyKit.xcframework` is absent or its hash does not match the pin. A runner with a verified framework reaches `cmux-unit`. The job does not need Depot, WarpBuild, Blacksmith, or `GLAEDA_ROUTE_APP_KEY` | Not run. Adding the workflow file is out of scope. `runs-on` in the proposal is `macos-26` because `.xcode-version` is `26` |

## Native boundaries, corrected

These are the cmux edits inside S3–S9. Sizes are estimates from the call sites, not measured patches. Thirty-day counts are `git rev-list --count upstream/main --since=2026-09-21` at the audited baseline.

| Boundary | Sites | Estimate | 30-day commits | Risk |
| --- | --- | --- | --- | --- |
| Panel type | `Panel.swift` case only; `PanelContentView.swift:55`; `SurfaceKind.swift:18-53` | ~40 lines | 6, 4, 3 | Medium. One missed switch is a compile error |
| Workspace persistence | Encode at `Workspace.swift:616`; `createPanel` at `:1621` and a restore arm beside `:2354` | ~120 lines | 159 | High |
| Dock persistence | `DockSplitStore+SessionSnapshot.swift:442`; `DockSplitStore+SessionRestore.swift:256` | ~40 lines | Counted with the dock files, not in the earlier hot-file table | Medium. Today's `default` drops the panel silently |
| Session payload | Optional fields on `SessionPanelSnapshot` (`SessionPersistence.swift:1780-1792`). Version stays 1 | ~40 lines | 18 | Medium. See S7 for downgrade |
| Lifecycle wiring | `applicationDidFinishLaunching` (`AppDelegate.swift:1691`), `applicationWillTerminate` (`:2573`). The supervisor type is new | ~40 lines at the call sites | 197 | High file, small hunk |
| Socket creation | `v2PanelType` (`TerminalControllerV2ParamParsingSupport.swift:189-208`) only if a socket client must create the pane | ~5 lines, or omit | — | Omit until needed. Default socket mode stays `cmuxOnly` |

`CLI/cmux.swift` (221 commits in 30 days) stays out. Domain rules stay in Studio.

## What stage 1 still does not include

- Copying Studio into this repository or into the `.app`.
- A second project database.
- An Electron process, or `afstudio-shell://` as the product UI.
- A workflow file, a dispatched Actions run, or a Ghostty pin move.
- Edits under the BUSL paths named in `LICENSE`.
- A remote-relay allowlist entry.
- Treating the license reading in ADR 0001 as a grant. Stage 2 still waits on ownership, a written grant, dependency notices, and corresponding source. The user and counsel decide whether a bundle is a combined work.
