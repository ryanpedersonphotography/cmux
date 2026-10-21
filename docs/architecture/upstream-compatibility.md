# Upstream compatibility

Audited commit, on both `origin/main` and `upstream/main`:

`72a39c338ef6e4d37e9ab29892f6561df1527781`

Date on that commit: 2026-10-20 17:46:57 -0700.
Subject: `ci: the owned-pool rescue never moves a nightly off its reserved runner or re-runs a superseded one (#22645)`.

The fork had no unique commits at audit time. `git merge-base HEAD upstream/main`
is that same SHA. Upstream was added as a remote and fetched. Nothing was
pushed to `manaflow-ai/cmux` or to any Ghostty repository.

## How fast main moves

Counts are `git rev-list --count upstream/main --since=<date>` on 2026-10-21:

| Window | Commits on `main` |
| --- | --- |
| Since 2026-09-21 (30 days) | 4,867 |
| Since 2026-10-14 (7 days) | 339 |
| Since 2026-10-20 (1 day) | 34 |

A long-lived fork that edits hot files will conflict every few days. The
practical rule is: add files, and touch `Workspace.swift`, `TerminalController.swift`,
and `CLI/cmux.swift` in the smallest possible hunks. Rebase onto upstream
often. Do not fork Ghostty again inside this repo.

## Files a project workbench would touch

Commit counts are `git rev-list --count upstream/main --since=2026-09-21 -- <path>`.

| Path | Commits in 30 days | Conflict risk | Why it would change |
| --- | --- | --- | --- |
| `CLI/cmux.swift` | 221 | High | Hook dispatch and CLI verbs live here. Avoid it. Put new commands in a new file if a CLI is required |
| `Sources/Workspace.swift` | 159 | High | Panel creation. One new method that calls out, not new state |
| `Sources/TerminalController.swift` | 128 | High | Legacy v2 `switch`. A new method belongs on `ControlCommandCoordinator` if it is needed at all |
| `docs/ghostty-fork.md` | 21 | High if edited | Do not edit. The pin moves without AgentFlow |
| `Sources/Feed/FeedCoordinator.swift` | 10 | Medium | Subscribe. Do not add a second waiter |
| `Sources/Panels/Panel.swift` | 6 | Medium | One enum case is a small, central conflict |
| `Sources/Panels/PanelContentView.swift` | 4 | Medium | One `switch` arm |
| `SurfaceCatalogModel.swift` | 4 | Low if left alone | Do not add a catalog kind for local panels |
| `Sources/CmuxEventBus.swift` | 4 | Low | Consume `seq` / `gap`. Do not change the buffer |
| `PaneTreeModel.swift` | 0 | Low | No API change expected |
| New `Packages/macOS/<domain package>/` | 0 | Low | Additive. This is the preferred place for project rules |

`Packages/macOS/CMUXProjectModel` is the Xcode project pane. Do not extend it
into a workbench. A new package avoids that name collision.

Ghostty pin `ef4f1570d62117ebc51e3b0f07ad4f34032267b6` and
`scripts/ghosttykit-checksums.txt:155` move when the terminal engine moves.
AgentFlow should not carry a Ghostty delta.

## Submodule pins recorded

| Path | Commit | License at that commit |
| --- | --- | --- |
| `ghostty` | `ef4f1570d62117ebc51e3b0f07ad4f34032267b6` | MIT (Mitchell Hashimoto and Ghostty contributors) |
| `vendor/bonsplit` | `d67d1b114fd20edba7a19f76cc39e35bde43c2d8` | MIT (Copyright 2026 Alasdair Monk) |
| `homebrew-cmux` | `a5f372ecfa5ee3903af6e1faba0eda096b4f5746` | Not opened. Packaging only |

Submodules were not checked out. Licenses were read from the pinned blobs.

## License boundary

Root `LICENSE` (lines 1-22): except where a file says otherwise, cmux is
GPL-3.0-or-later. The macOS app, iOS app, CLI, and `cmux-tui` client stay
under that file. `coderouter/LICENSE` is also GPL-3.0-or-later.

BUSL-1.1, each with its own `LICENSE`, confirmed by reading the first lines:

- `web/`
- `workers/ci-artifacts/`
- `workers/iroh-v2/`
- `workers/presence/`
- `services/iroh-relay-minter/`
- `cmux-tui/relays/cloudflare-do/`

Each of those licenses names Manaflow, Inc. as licensor, Additional Use
Grant none, Change Date four years from publication, Change License
GPL-3.0-or-later. Production use, including self-hosting, needs a commercial
license from Manaflow. This audit did not copy or build them.

Not named in the root BUSL list, and not given a clean license of their own:

- `workers/cmux-paste-text/` — one Objective-C file, no `LICENSE`, no header.
  It is a macOS paste helper, not one of the server directories. The root
  license would cover it only because it is not carved out. Treat that as
  GPL-by-default and do not move it.
- `workers/fleet-artifacts/` — no `license` field in `package.json`, no
  `LICENSE` file, not listed in root `LICENSE`. Status is unverified. Do not
  import it, and do not assume it is GPL.

`THIRD_PARTY_LICENSES.md` records MIT, BSD, and Apache notices for bundled
libraries. Ghostty and bonsplit are MIT at the pins above. Those notices
have to ship with a binary. GPL does not relicense them.

Tellurion (`41a91325f7298baee7957a39757ceae558a8fee8`) is AGPL-3.0. No code
from it is in this tree. Copying it into a GPL app would put the combination
under AGPL terms. Do not copy it.

myzig (`4203821d13d63b1c1a9b24ac392145273211bda3`) is MIT. This audit copies
no source from it. Principles are restated in
[target-architecture.md](target-architecture.md).

## CLA

`CLA.md` is Individual Contributor License Agreement v2.2 with Manaflow, Inc.
`CONTRIBUTING.md` (around line 145) tells upstream contributors to comment
`I have read the CLA Document v2.2 and I hereby sign the CLA` on their pull
request. `.github/workflows/cla.yml` and `cla-policy-guard.yml` enforce that
on the upstream repository. The CLA grants Manaflow a license to the
contribution. It is not the distribution license.

A downstream fork that never sends patches to `manaflow-ai/cmux` does not
need its users to sign Manaflow's CLA. Anyone who wants a patch accepted
upstream does. This audit does not sign the CLA and does not open an
upstream pull request.

## Distributing a GPL fork

This is a reading of the licenses in the tree, not legal advice.

If you distribute binaries of a modified cmux:

- Ship this `LICENSE` text and keep the copyright notices (`LICENSE` lines
  1-8, and GPL section 4-5: mark the work as changed, keep notices).
- Offer the corresponding source of the GPL work, including this fork at the
  commit you built, under GPL-3.0-or-later. The Ghostty MIT sources used to
  build GhosttyKit are part of what a recipient needs in order to rebuild;
  the checksum pin records which binary you shipped.
- Keep `THIRD_PARTY_LICENSES.md` and the Ghostty and bonsplit MIT notices.
- Do not strip the GPL and relicense the app as MIT or as a proprietary
  binary. A GPL-3.0-or-later derivative stays under that license when you
  distribute it.
- Leave the BUSL directories out of the product unless you have a separate
  commercial grant. "The Change License becomes GPL in four years" is not a
  present grant.
- Do not combine AGPL Tellurion code with this tree.
- A separate process that only speaks the documented socket protocol, and
  contains no cmux source, is a licensing question this audit does not
  decide. Code added inside this repository should stay GPL-3.0-or-later and
  should not carry a conflicting license header.

## Merge practice

Prefer a package under `Packages/macOS/` and a thin panel adapter. Record
the upstream SHA in every phase checkpoint. When `main` moves, merge it;
do not rebase published history that other people have pulled, and do not
force-push over a merge commit created to catch up. Do not open pull
requests against `manaflow-ai/cmux` for AgentFlow.
