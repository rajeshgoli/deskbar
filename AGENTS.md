# Working in this repo

I am Rajesh. I own this repo and I'm the only human who works on it. DeskBar is a native macOS taskbar replacement written in Swift/AppKit and built with Swift Package Manager. It runs all day on my machine from `/Applications/DeskBar.app`, so a broken build is something I feel immediately. It also shows my Session Manager agents in the taskbar (the SM plugin), so it depends on the `sm` server's HTTP API.

This file is the whole standing contract. Read all of it.

---

## 1. Writing for me

**Define every term before you use it.** Name a phase, gate, structure, or abbreviation and define it in plain words at first use. Never assume a term from an earlier document stuck in my memory. Terms I coined, like `sm send`, `sm queue run`, and `sm request-codex-review`, have precise meanings and I understand them, so use them when you mean them. Recent ticket or decision shorthand (T1a, R1, D1b) means nothing to me.

**Write in executive style.** Start with the conclusion, then justify it. Use active sentences: "I did X", not "X has been completed". Write for someone tired, reading at 2 a.m., who is new to the thread.

**Show me, don't describe.** DeskBar is visual. For a UI change, a before/after screenshot beats a paragraph. Use charts, diagrams, or tables to explain concepts.

**Give me decisions and options, not questions.** Bring only what I alone can decide, with a recommendation and a reason. "Should we delete this?" is not a question for me; "I recommend deleting this because X. Confirm?" is. If the decision doesn't need me, make it and tell me.

**Reach me in-session, in prose.** Don't use AskUserQuestion unless I ask you to interview me. I'm often on my phone, so prose and one question at a time work best. Email (`sm email rajesh`) only on my standing ask, at an event I named, or after roughly seventeen minutes of silence, which means I stepped away. Batch your questions in an email and say in the subject if it blocks.

**`SPEC.md` is the authoritative product and implementation spec.** If your change alters behaviour that `SPEC.md` specifies, update `SPEC.md` in the same PR. Write it in the present tense, as though it always said this. Design docs for work in progress go in `docs/working/`. If you need me to read a doc, commit and push it, then publish it with `sm doc publish <path>`. If you need my review, open a PR containing it and run `sm doc publish <path> --pr <N> --review`.

---

## 2. Cost and context

**Token budget beats wall-clock.** Running out of tokens stops all work until a quota reset that can be a week away. Wall-clock delay costs hours. When the two conflict, spend time and save tokens.

**Match the model to the work.** Ill-defined problems, design authority, and spec authorship take the top tier. Well-specified implementation and review take the middle tier. Mechanical work, such as inventory, fixture plumbing, and narrow docs, takes the low tier. State the tier and effort explicitly on every spawn.

| Tier | Claude | Codex |
|---|---|---|
| Top | fable, xhigh effort | astra, high effort |
| Mid | opus 1M, high | terra, high or sol, medium |
| Low | sonnet 1M, high | luna, high |

**Don't delegate your core task.** You may use lower-tier subagents for research, lookup, and inventory. Unless I say you are an orchestrator, you do the implementation, spec, or review I assigned yourself.

**One agent, one task.** Retire when you finish. **A ticket is what one agent can finish without compaction.** If it doesn't fit, split it before briefing anyone.

**Use `sm send` between agents only if you're told to.** Never poll another agent's output. Go idle and you will be woken. **When told to stand by, go idle.**

**On `[sm remind]`, run `sm status "what you are doing now"` and carry on.** It is not an interrupt.

**Long-running commands go through Session Manager from the start.** Submit them with `sm queue run --type <tests|perf|background> --label <label> --cwd <worktree> -- <command>`, then go idle. The queue wakes you with `[sm queue]` when the job finishes. Don't add a second watcher, `sleep`, `tail -f`, or poll.

**Split parallel work across non-overlapping file sets.** A worktree keeps agents from corrupting each other's git state, but it doesn't stop two tickets from editing the same file and colliding at merge. Much of DeskBar lives in a few large files (`TaskbarContentView`, `SMPluginService`, `TaskButtonView`, `WindowManager`). If two tickets touch the same one, do them one after the other.

**Never wrap a message that contains backticks or `$()` in double quotes.** The shell substitutes before Session Manager sees the message. Use single quotes, a heredoc, or a file payload.

**Report `sm` bugs instead of working around them.** File them in `rajeshgoli/session-manager`, then reach its maintainer: run `sm lookup maintainer` to get the session id, then `sm send <id>` with the description and the issue link. This includes a change to the `sm` HTTP API that breaks the SM plugin. Fix the plugin here only if the new API behaviour is intended.

---

## 3. Your workflow

**Name yourself.** Before you start, check your name with `sm me`. If it's `claude-<slug>`, `codex-fork-<slug>`, or similar, rename yourself with `sm name db-<newname>`. `db-<ticket>-engineer`, `db-<ticket>-scout`, `db-<ticket>-spec-author`, `db-<ticket>-spec-reviewer`, and `db-<pr>-reviewer-<round>` all beat `claude-<slug>`, because a name that says what you were doing is how I restore you. The `db` prefix tells me you're working on DeskBar and not my primary repo.

**Work in your own worktree, never in `~/projects/deskbar`.** Every agent works in its own worktree under `~/worktrees/db-<ticket>-<slug>` and keeps build outputs (`.build/`) inside it. `~/projects/deskbar` is the shared checkout. It stays on `main` and is used only to build the installed app after a merge (step 7). Several agents run at once. Switching branches or building in the shared checkout has moved files out from under another agent mid-edit and broken its build.

**Claim your work.** Start a ticket with `sm ticket <N> --setup-worktree` and work in the worktree it prints. Use plain `sm ticket <N>` if you already have a worktree. When you open a PR, or take over someone else's, run `sm pr` from its branch. Put `Closes #<N>` in the PR body for each ticket the PR finishes; "Implements #N" doesn't close it. Reviewers and scouts don't claim work. When you retire, sm deletes your worktree if nothing would be lost. If something there must outlive you, run `sm worktree keep --reason "<why>"`.

`[sm claim]` messages state facts. Act on them like this:
- Your claim is refused because another live agent holds it: stop and tell me. Use `--take` only when I say so.
- Another agent claimed your ticket or PR: stop working on it and tell your parent or me what state you left it in.
- A merged PR's ticket is still open: if the PR finished it, close it (`gh issue close <N> --comment "Done in #<P>"`). Otherwise, comment on the ticket what remains.
- You hold open work at task-complete or while idle: if you're waiting on me, stay idle. If you're finished, merge the PR once its review is clean, make sure the ticket closes, and run `sm task-complete`. If you're not finished, comment on the ticket what remains, then continue or stand by.

Workflow as usual:
1. Build, test, and install your branch's build so it can be verified live (see "Install and restart" in section 5). A change that only touches tests or docs doesn't need an install. Only one DeskBar can run at a time. If another `db-` agent in `sm all` looks like it's testing a live build, ask me before replacing it.
2. Test directly when you can. For example, if you can reproduce the issue I reported and then verify it no longer happens, tell me what you did and optionally ask me to try it. If I need to test something, tell me exactly what to do and what I should see, such as "open three Terminal windows, minimize the middle one, and check that it moves to the tray".
3. When all requested changes are done and verified, go to step 4. If I have feedback or you find live failures, repeat steps 1 and 2.
4. Create a PR. Include what you verified live and how.
5. Use the review loop in section 4 to get the PR into a clean, mergeable state.
6. Once it's clean, run `gh pr merge --squash --delete-branch --match-head-commit <reviewed sha>`. If the merge is blocked by conflicts or failing checks, fix it or ask me. Then delete any local branches and worktrees you created.
7. In `~/projects/deskbar`, run `git pull --ff-only`, then install from there (section 5), so the running app is `main` and not your branch.
8. Tell me.

---

## 4. Review loop

Request a review with `sm request-codex-review <pr-number>`. Treat the response as registration only, then go idle; don't poll. If Session Manager can't take the request, post `@codex review` as a PR comment and check back after five minutes, then again after five more. If codex hasn't acknowledged it with a 👀 reaction after 10 minutes, you can post the request again. If nothing has landed after 20 minutes, you can post it again.

Before acting on a review, confirm it belongs to your current request and was posted after your latest push. The existence of a review isn't enough.

Then:

1. **Classify every finding as valid, partially valid, or invalid.** Don't skip this. A review isn't gospel; push back with reasoning where it's wrong.
2. **Correctness only.** No document nits, wording preferences, or process-for-its-own-sake nits. That excludes process *preference*, not process *correctness*. When the thing under review is a workflow, an instruction file, CI, or a build script, its behaviour is the correctness surface. "This installs an ad-hoc-signed build" is a bug, not a nit.
3. **Any unresolved P1 blocks.** A P1 is resolved either by fixing it or by answering it. A P1 you classify as invalid, with your reasoning posted on the PR, is resolved and doesn't block. If the reviewer raises the same P1 again after reading your reasoning, that's a real disagreement: escalate it to me instead of looping. A round that returns only P2 or lower, or a clean review, ends the loop. Don't keep chasing P2s and P3s.
4. Fix, push, and request a new review at the exact head. Aim for the fewest rounds to correctness, which doesn't mean dropping correctness issues.

---

## 5. Repo reference

Pure AppKit, no SwiftUI, and no dependencies beyond system frameworks. Targets macOS 14+.

- `Sources/DeskBar/App/`: `AppDelegate` (startup, status item, signal handling), `SingleInstanceLock`, `PermissionsManager`
- `Sources/DeskBar/Services/`: `WindowManager` (the window list, from Accessibility observers plus CGWindowList polling), `AccessibilityService`, `ThumbnailService` (ScreenCaptureKit), `WindowSwitcherService` (Option+Tab), `DockManager`
- `Sources/DeskBar/Views/`: `TaskbarPanel`, `TaskbarContentView`, `TaskButtonView`, `SettingsView`
- `Sources/DeskBar/Plugins/SMPlugin/`: the Session Manager plugin. It polls the `sm` server's `/sessions` and `/session-obligations` endpoints and maps agents to terminal windows.
- `Tests/DeskBarTests/`: XCTest unit tests
- `docs/working/`: in-progress design docs and the backlog

```bash
swift build        # debug build
swift test         # full test suite; must pass before you open a PR
```

A fresh debug build takes under a minute and `swift test` takes about 30 seconds, so run both inline, not through `sm queue`. The build has existing warnings, and there's no lint gate.

**Install and restart.** Run these from your worktree, or from `~/projects/deskbar` for the post-merge install:

```bash
swift build -c release
DESKBAR_REQUIRE_SIGNING=1 bash scripts/package.sh
pkill -x DeskBar; ditto .build/release/DeskBar.app /Applications/DeskBar.app
open /Applications/DeskBar.app
```

**Always package with `DESKBAR_REQUIRE_SIGNING=1`.** macOS ties the Accessibility and Screen Recording grants to the app's code signature. `scripts/package.sh` signs with the persistent certificate in `config/signing.env`. Without the flag, a missing certificate falls back to ad-hoc signing, and installing that build silently revokes both grants, so I have to re-approve them by hand. Install with `ditto`, not `cp -r`, which can break the signature.

**Quit DeskBar with SIGTERM (`pkill -x DeskBar`), never `kill -9`.** DeskBar can auto-hide or hide the Dock. SIGTERM runs its Dock restore; SIGKILL leaves the Dock hidden until the `com.deskbar.dock-watchdog` LaunchAgent catches up.

**Live state lives outside the checkout:** `~/Library/Preferences/com.deskbar.app.plist` (settings), `~/.config/deskbar/` (single-instance lock and saved Dock state), and `~/Library/LaunchAgents/com.deskbar.*.plist` (start at login and the Dock watchdog). Don't delete these to "reset" DeskBar. Ask me.

**Your terminal can't see what DeskBar sees.** Window enumeration, titles, and thumbnails depend on permissions granted to `DeskBar.app`, not to your shell. Verify window behaviour against the installed app, not by calling Accessibility APIs from a script.
