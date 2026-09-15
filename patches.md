# Patches — Now-Playing Title + Remappable Launcher Button

Base: `main @ 0fcf06a` (pulled `origin/main`, already up to date on 2026-09-15).
Branch: `feature/now-playing-title-remappable-launcher`

Decisions (from user):
- Music scope: any Now Playing source (Music, Spotify, browsers) via system Now Playing.
- Launcher remap: any app + custom command/URL + hidden/disabled option.
- Title behavior: song replaces window title only while `isPlaying == true`; otherwise fallback to AX/CG title.

Constraints:
- SPEC: system frameworks only, no bundled 3rd-party helper. So no `mediaremote-adapter` framework/perl bundle.
- Direct `MediaRemote.framework` linking is entitlement-gated on macOS 15.4+. Use `/usr/bin/osascript` JXA bridge to `MRNowPlayingRequest` + per-app AppleScript fallback. Poll, don't stream.
- `WindowInfo.title` is part of `Equatable/id` — do NOT mutate it per-track. Override at display layer (`TaskButtonView.resolvedTitle()`), mirroring SM-agent `friendlyName` precedent.

Slice order matters (each slice builds + tests green before next). Slices are sized for one agent context each.

---

## Slice 1 — Settings model foundation (both features)

Goal: persist new prefs with zero-migration defaults.

Files:
- Modify: `Sources/DeskBar/Models/TaskbarSettings.swift`
- Modify/extend: `Tests/DeskBarTests/TaskbarSettingsTests.swift` (check existing name first)

Changes:
- `showNowPlayingTitles: Bool = true` (key `"showNowPlayingTitles"`).
- `LauncherButtonAction: String enum { systemApps, customApp, customCommand, hidden }`.
- `launcherButtonAction: LauncherButtonAction = .systemApps` (key `"launcherButtonAction"`).
- `launcherCustomAppBundleID: String?` + `launcherCustomAppPath: String?` (keys as-named, nil = unset).
- `launcherCustomCommand: String = ""` (key `"launcherCustomCommand"`).
- Init loaders + `didSet` persisters follow existing pattern. Absent keys → defaults above.

Accept:
- Fresh launch keeps old behavior (system Apps button, no title change unless playing).
- New keys round-trip through UserDefaults.

Verify: `swift build` + `swift test --filter TaskbarSettings`.

---

## Slice 2 — NowPlayingService (new file + tests)

Goal: poll system Now Playing without private-framework linking.

Create:
- `Sources/DeskBar/Services/NowPlayingService.swift`
  - `struct NowPlayingSnapshot { bundleIdentifier: String?, appName: String?, title, artist, album, isPlaying: Bool }`
  - `var displayString: String` → `"Artist – Title"`, title-only fallback, empty-trimmed.
  - `final class NowPlayingService: ObservableObject { @Published var snapshot: NowPlayingSnapshot? }`
  - Reader runs off-main-thread: `Process(/usr/bin/osascript)` + short JXA hitting `MRNowPlayingRequest.localNowPlayingPlayerPath/client/displayName` + `localNowPlayingItem.nowPlayingInfo` (`kMRMediaRemoteNowPlayingInfo{Title,Artist,Album}`) + playback state. 1s timeout, parse `title - album - artist | appName`-style output.
  - Fallback when bridge empty: `tell application "Music"/"Spotify" to get {artist, name} of current track + player state is playing`.
  - `isPlaying == false` → publish `nil` (callers fall back to window title).
  - `start(pollInterval: 2.0)` / `stop()`; 2s cadence to match existing CGWindowList poll. No-op when `showNowPlayingTitles == false` (caller gates).
Create:
- `Tests/DeskBarTests/NowPlayingServiceTests.swift` — pure-logic tests: display-string formatting, empty-field handling, paused→nil mapping, output-line parser. No live-media dependency.

Accept:
- No new package dependency. No MediaRemote link. Service publishes nil when paused/stopped.

Verify: `swift build` + `swift test --filter NowPlaying`.

---

## Slice 3 — Task button title override (display layer)

Goal: music-app windows in Task Zone show song while playing.

Files:
- Modify: `Sources/DeskBar/Views/TaskButtonView.swift` (`resolvedTitle() ~:782`, `resolvedToolTip() ~:808`, cancellables `~:771-779`, `update(...) ~:1179`)

Changes:
- Inject/observe `NowPlayingService` (same Combine pattern as `settings.$...` subscriptions). On `snapshot` change → `updateAppearance()`.
- In `resolvedTitle()`, before `windowInfo.title` fallback (after SM-agent block):
  `if settings.showNowPlayingTitles, let snap, snap.isPlaying, snap.bundleIdentifier == windowInfo.bundleIdentifier → return snap.displayString`
- `displayTitle()` decorators (`[minimized]`/`(hidden)`) stay untouched — they wrap the resolved string.
- Tooltip: line 1 = song string; append raw window title as second line when overridden (same pattern as SM-agent `Terminal:` line at `:832-835`).
- No changes to `WindowInfo.swift`, `WindowManager.swift`, `AccessibilityService.swift`.

Accept:
- Music/Spotify/browser window shows `Artist – Title` only while playing; pause/stop reverts instantly; other apps unaffected; minimized/hidden brackets still apply.

Verify: `swift build`; manual with Music + Spotify play/pause; `swift test`.

---

## Slice 4 — Launcher resolver + button behavior + hide

Goal: button target remappable, hideable; shortcut follows remap.

Files:
- Modify: `Sources/DeskBar/Utilities/AppsLauncher.swift` — add `resolve(settings:) -> (name, icon, tooltip)` + `open(settings:)` with branches: `.systemApps` (existing bundle/fallback logic), `.customApp` (`urlForApplication(bundleID)` or stored path → `LauncherApplicationActivator.launch`), `.customCommand` (URL-string → `NSWorkspace.open`; else `/bin/sh -c`), `.hidden` (no-op).
- Modify: `Sources/DeskBar/Views/AppsLauncherButtonView.swift` — `init(settings:)`, subscribe to `$launcherButtonAction/$launcherCustomAppBundleID/$launcherCustomAppPath/$launcherCustomCommand` for live icon/tooltip refresh; click → `open(settings:)`; context menu keeps "Open …" + adds "Configure Launcher Button…" (opens Settings > Launcher).
- Modify: `Sources/DeskBar/Views/LauncherZoneView.swift` (`rebuildButtons():165`, `preferredContentWidth():52-62`) — skip button creation/width when `.hidden`.
- Modify: `Sources/DeskBar/Services/WindowSwitcherService.swift` (`:88-120,333-376`) — pass settings into `AppsLauncher.open(settings:)` so the keyboard shortcut fires the remapped target.

Accept:
- Default = today's Apps behavior. Custom app changes icon/tooltip/action. Bad path/URL logs + no-ops (no crash). Hidden removes button and reclaims width. Shortcut opens remapped target.

Verify: `swift build`; manual: remap via defaults-write first (UI lands in Slice 5), toggle hidden, test shortcut.

---

## Slice 5 — Settings UI (Behavior + Launcher tabs)

Goal: user-configurable without plist hacking.

Files:
- Modify: `Sources/DeskBar/Views/SettingsView.swift`
  - Behavior tab (~`:142-157`): checkbox "Show currently playing song as window title" bound to `showNowPlayingTitles` (+ `showNowPlayingTitlesChanged` action).
  - Launcher tab (~`:182-184,802-827`): "Launcher Button" section — popup (System Apps / Custom App / Custom Command / Hidden) + [Choose App…] (`NSOpenPanel`, `/Applications`, `*.app` → sets bundleID+path, shows name/icon) + command/URL text field + Test button. Enable/disable controls per mode (same pattern as `:636-661`).
- No model changes (uses Slice 1 keys).

Accept:
- All four modes selectable, picker/field enablement correct, Test fires same path as button click, prefs persist across relaunch.

Verify: `swift build`; manual through Settings UI; `swift test`.

---

## Slice 6 — Docs + final hardening

Goal: converge spec/docs, handle edge cases, green suite.

Files:
- Modify: `SPEC.md` (settings table ~Phase 5 + Apps-launcher row in Feature-to-API mapping + Task Model Rules note for title override + launcher modes).
- Optional: `README.md` usage row for remapped launcher + Now Playing note.
- Harden: invalid custom command surfacing (log, keep old icon), `osascript` failure → silent nil (no banner), browser NowPlaying maps to that browser's windows only, degraded (no-AX) mode still shows song titles (display-only, no AX needed).

Accept:
- `swift build` clean, `swift test` green, `scripts/build.sh` bundles (if run).
- Manual checklist: play/pause in Music, Spotify, YouTube-in-browser; remap to app, URL, shell, hidden; relaunch persistence; shortcut follows remap; Cmd+Tab/Space unaffected.

Verify: `swift build && swift test`.
