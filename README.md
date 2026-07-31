# Badgeify Clone

A menu bar app that mirrors your apps' unread badges into the macOS menu bar — a
functional clone of [Badgeify](https://badgeify.app) with no feature gating: unlimited
menu bar items, and every behavior option unlocked.

Built with SwiftPM + AppKit/SwiftUI, so it compiles with **Command Line Tools only** (no
Xcode needed).

## Build & run

```sh
./build.sh          # → build/Badgeify.app
open build/Badgeify.app
```

Then grant Accessibility access (see below). The app has no Dock icon; it lives in the
menu bar, and `⌘,` from its right-click menu (or the optional global shortcut) opens
Settings.

## Accessibility permission — required

Badge counts are read from each app's **Dock tile** via the Accessibility API
(`AXStatusLabel` on Dock items, resolved to a bundle through `AXURL`). This is the only
public way to observe another app's badge, so:

1. Open Settings → **General** → **Grant Access…**
2. Enable the entry in System Settings → Privacy & Security → Accessibility.
   Two rows are named `Badgeify.app` if the original is also installed — ours is the one
   whose icon is the blue tile with a red badge.
3. The banner clears itself within ~2s. If it doesn't, click **Already granted? Relaunch**.

### Making the grant survive rebuilds

Run this once:

```sh
./scripts/create-signing-identity.sh
```

It creates a self-signed code-signing certificate ("Badgeify Local Signing") in your login
keychain, and `build.sh` uses it automatically. The designated requirement becomes

```
identifier "com.local.badgeify" and certificate leaf = H"<cert hash>"
```

— no cdhash, so **rebuilds no longer void the Accessibility grant**. Verified: rebuilt with
a changed cdhash and the app still reported `access=true` without re-granting.

Remove the certificate with `security delete-identity -c "Badgeify Local Signing"`.
Override the identity with `CODESIGN_IDENTITY="..."`.

Things to know about how this works:

- **Without that certificate the signature is ad-hoc, and the grant is bound to the binary's
  cdhash.** Rebuilding then voids it *while System Settings still shows the toggle as ON* —
  the app is denied and the UI lies about it. In that fallback mode `build.sh` runs
  `tccutil reset Accessibility com.local.badgeify` whenever the signature changes, so a
  missing grant at least looks missing (`SKIP_TCC_RESET=1` opts out).
- **macOS only reports a *new* grant to newly started processes.** `AXIsProcessTrusted()`
  is latched at launch, so an instance that was running when you flipped the toggle keeps
  reporting "no access" forever. The app ignores that flag and tests access functionally
  (an actual Dock read), so it recovers within ~2s; the banner's **Relaunch** button is the
  fallback.
- **An app must be in the Dock** for its unread count to be readable. The info (ⓘ) button
  next to each item warns when an app isn't in the Dock.

### Checking whether access really works

Do **not** trust running the binary from a terminal:

```sh
./build/Badgeify.app/Contents/MacOS/Badgeify --dump-badges   # MISLEADING
```

TCC attributes Accessibility calls to the *responsible* process, so a binary started from
a terminal inherits the terminal's (or IDE's) own grant and reports success even when the
app itself is denied. The honest signal is what the real app process records each refresh:

```sh
defaults read com.local.badgeify diagnostics
# access=true badges=2 items=2
```

`BADGEIFY_DEBUG=1` on the app logs the same per-refresh detail to stderr.

`BADGEIFY_DEBUG=1` on the app itself logs each refresh cycle to stderr.

## Features

**General**
- Open at login (`SMAppService`)
- Show settings window on startup
- Menu Bar Items: add via the app picker or **Browse…**, drag to reorder, per-app
  enable toggle, ⓘ details popover, remove with **−**. No item limit.

**Advanced**
- Language (System Default / English)
- Icon size — Small / Medium / Large
- Unread status refresh rate — Slow 5s / Normal 2s / Fast 1s / Realtime 0.4s
- Unread activity animation — None / Bounce / Pulse / Blink
- When there are no unread items — Always Show / Dim Icon / Hide
- When not running — Always Show / Dim Icon / Hide
- Settings window shortcut — global hotkey, click the button to record a new combination
- When clicking an app icon — Show Only / Show or Hide / Show and Hide Others
- Settings backup — Import / Export as JSON

**Keyboard**
- `⌘Q` quits Badgeify, `⌘W` closes the settings window, `⌘,` reopens it. An accessory app
  shows no menu bar, so these come from an `NSApp.mainMenu` installed at launch purely for
  key-equivalent dispatch (which also gives text fields ⌘C/⌘V/⌘X/⌘A).
- `Badgeify --selftest-cmdq` pushes a synthetic ⌘Q through `NSApp.sendEvent` and reports
  whether it reaches Quit — a way to test the shortcut without stealing focus.

**Menu bar item interaction**
- Left click: activate (or launch) the app, per the click-behavior setting
- Right click: bring to front, quit the app, remove from menu bar, open Settings, quit
  Badgeify

**Updates / About** panes are present; there is no update server, so *Check Now* is a
no-op.

## Layout

| File | Role |
| --- | --- |
| `Sources/Badgeify/main.swift` | Entry point, app delegate, settings window controller |
| `Sources/Badgeify/Settings.swift` | Option enums, `SettingsData`, persisted `SettingsStore` |
| `Sources/Badgeify/DockBadgeReader.swift` | Accessibility walk over the Dock |
| `Sources/Badgeify/MenuBarManager.swift` | `NSStatusItem` lifecycle, refresh/animation timers, clicks |
| `Sources/Badgeify/IconRenderer.swift` | Icon + badge compositing |
| `Sources/Badgeify/SystemIntegration.swift` | Login item, Carbon global hotkey, app discovery |
| `Sources/Badgeify/SettingsView.swift` | Sidebar shell and the four panes |
| `Sources/Badgeify/AppPickerView.swift` | Installed-app picker sheet |
| `Sources/Badgeify/Components.swift` | Card/row/picker/recorder building blocks |

Settings persist in `UserDefaults` under `settings.v1` for bundle id
`com.local.badgeify`.

## Notes

- If the real Badgeify is also installed and running, you'll see duplicate icons — quit
  one of them. `CFBundleName` here is "Badgeify Clone" to keep the two apart in Login
  Items.
- Moving the bundle (e.g. into `/Applications`) changes its TCC identity, so
  Accessibility must be granted again at the new location. *Open at login* is most
  reliable with the app in `/Applications`.
- Status item ordering follows the settings list; macOS hides items that don't fit when
  the menu bar is crowded.
