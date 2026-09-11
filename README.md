# Badges

A menu bar app that mirrors your apps' unread counts into the macOS menu bar.

Counts come from an app's Dock badge *or* from its window title, chosen per app — so apps
like Signal, which only ever show the count in the title bar (`Signal (1)`) and leave the
Dock tile bare, still work.

Built with SwiftPM + AppKit/SwiftUI, so it compiles with **Command Line Tools only** (no
Xcode needed).

## Build & run

```sh
./build.sh          # → build/Badges.app
open build/Badges.app
```

## Detection mode

Set per app, in the picker next to each menu bar item:

| Mode | Reads |
| --- | --- |
| **Auto** (default) | the Dock badge, falling back to the window title |
| **Dock Badge** | the Dock tile only |
| **Window Title** | the `(n)` in the app's window title only |

`Badges --dump-titles` lists every running app's window titles and the count each would
parse to, for deciding which apps suit Window Title mode.

## Accessibility permission — required

Unread counts are read through the Accessibility API — from each app's **Dock tile**
(`AXStatusLabel` on Dock items, resolved to a bundle through `AXURL`) and from its
**window titles** (`AXWindows` → `AXTitle`). Those are the only public ways to observe
another app's unread count, so:

1. Open Settings → **General** → **Grant Access…**
2. Enable the entry in System Settings > Privacy & Security > Accessibility.
   Two rows appear if the original Badgeify is also installed — ours is named `Badges.app`.
3. The banner clears itself within ~2s. If it doesn't, click **Already granted? Relaunch**.

Settings persist in `UserDefaults` under `settings.v1` for bundle id `com.local.badges`.
The app was previously called Badgeify; on first launch, settings are migrated across from
the old `com.local.badgeify` domain if the new one is empty.
