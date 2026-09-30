# 1. Working in this repo

I am Rajesh, I own the repo and am the only human on it. DeskBar is a native macOS taskbar replacement built with Swift/AppKit and Swift Package Manager. It runs all day on my machine from `/Applications/DeskBar.app`, and its SM plugin shows my Session Manager agents in the taskbar.

This file is the whole standing contract. Read all of it.

## 2. Your workflow

**Name yourself.** Before you begin work, check your name with `sm me`. If it is `claude-<slug>`, `codex-fork-<slug>`, or anything similar, replace it with `sm name db-<newname>`. `db-<ticket>-engineer`, `db-<ticket>-scout`, `db-<ticket>-spec-author`, `db-<ticket>-spec-reviewer` and `db-<pr>-reviewer-<round>` all beat `claude-<slug>`, because a name that says what you were doing is what lets me restore you. The `db` prefix lets me know you're working on DeskBar as opposed to my primary repo without needing to dig deeper.

**Worktrees.** Every agent works in its own worktree under `~/worktrees/db-<ticket>-<slug>`, build outputs inside. Never switch branches or build in `~/projects/deskbar`: other agents share it, and it stays on `main` for step 7.

**Claim your work.** Start a ticket with `sm ticket <N> --setup-worktree` and work in the worktree it prints (plain `sm ticket <N>` if you already have one). When you open a PR, or take over someone else's, run `sm pr` from its branch. Put `Closes #<N>` in the PR body for each ticket the PR finishes; "Implements #N" does not close it. Reviewers and scouts don't claim. When you are retired, sm deletes your worktree if nothing would be lost; if something there must outlive you, run `sm worktree keep --reason "<why>"`.

Workflow as usual:
1. Run `swift test`, then install your build and restart DeskBar (see Repo reference). Test- or docs-only changes don't need an install.
2. If I need to test something let me know exactly what to try out. If you can test directly that's preferred. For example, if you can reliably reproduce the issue I reported and you can verify it no longer occurs, you can tell me what you did and ask me to try it optionally.
3. Once all feature requests above are completed and verified, you may exit to step 4. If I have feedback or if you find live test failures, repeat steps 1 and 2 until exit to 4 criteria is met.
4. Once functionality is in place, create a PR for your changes.
5. Use instructions in Review loop section to get your PR in a clean mergeable state.
6. Once clean, `gh pr merge --squash --delete-branch --match-head-commit <reviewed sha>`. For any blocker, such as conflicts, fix it or ask me. Then delete any local branches and worktrees you created.
7. In `~/projects/deskbar`: `git pull --ff-only`, then install and restart from there, so the running app is `main` rather than your branch.
8. Let me know.

## 3. Review loop

**Requesting a review.** Request with `sm request-review <pr-number>`. This is registration only; sm picks the reviewer and wakes you when the review is on the PR. Go idle and wait — do not poll. If sm refuses, or wakes you saying no reviewer could take it, tell me and stand by. Do not post `@codex review` yourself.

Before acting on a review, confirm it belongs to your current request and was posted after your latest push. A review existing is not enough on its own.

Then:

1. **Classify every finding: valid, partially valid, or invalid.** Do not skip this. A review is not gospel — push back with reasoning where it is wrong.
2. **Correctness only** — no document nits, no wording preferences, no nits about following process for process's sake. That excludes process *preference*, not process *correctness*: when the thing under review is a workflow, an instruction file, CI, or a build script, its behaviour is the correctness surface, and a defect in it is a correctness finding however procedural it sounds.
3. **Any unresolved P1 blocks.** A P1 is resolved either by fixing it or by answering it: a P1 you classify invalid, with your reasoning posted on the PR, is resolved and does not block. If the reviewer re-raises the same P1 after reading your reasoning, that is a real disagreement: escalate it rather than looping. A round that returns only P2 or lower, or a clean review, exits the loop. Do not keep chasing P2s and P3s.
4. Fix, push, and re-review at the exact head. Fewest rounds to correctness — which does not mean dropping correctness issues.

## 4. Repo reference

- `Sources/DeskBar/App/` - `AppDelegate`, single-instance lock, permissions
- `Sources/DeskBar/Services/` - `WindowManager` (window list), `AccessibilityService`, `ThumbnailService`, `WindowSwitcherService` (Option+Tab), `DockManager`
- `Sources/DeskBar/Views/` - `TaskbarPanel`, `TaskbarContentView`, `TaskButtonView`, `SettingsView`
- `Sources/DeskBar/Plugins/SMPlugin/` - Session Manager plugin; polls the `sm` server's `/sessions` and `/session-obligations`
- `Tests/DeskBarTests/` - unit tests (`swift test`)
- `SPEC.md` - product spec

Install and restart:

```bash
swift build -c release &&
DESKBAR_REQUIRE_SIGNING=1 bash scripts/package.sh &&
{ pkill -x DeskBar; while pgrep -xq DeskBar; do sleep 0.2; done; } &&
ditto .build/release/DeskBar.app /Applications/DeskBar.app &&
open /Applications/DeskBar.app
```

The `&&` chain stops at the first failure, so a failed build never installs a stale binary. The loop waits for the old DeskBar to exit before replacing it.

`DESKBAR_REQUIRE_SIGNING=1` matters: an ad-hoc-signed install loses the Accessibility and Screen Recording grants and I have to re-approve them. Quit with `pkill` (SIGTERM), never `kill -9`, so DeskBar restores the Dock on the way out.
