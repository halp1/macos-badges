# Badges

A menu bar app that mirrors your apps' unread badges into the macOS menu bar.

Built with SwiftPM + AppKit/SwiftUI, so it compiles with **Command Line Tools only** (no
Xcode needed).

## Build & run

```sh
./build.sh          # → build/Badgeify.app
open build/Badgeify.app
```

## Accessibility permission — required

Badge counts are read from each app's **Dock tile** via the Accessibility API
(`AXStatusLabel` on Dock items, resolved to a bundle through `AXURL`). This is the only
public way to observe another app's badge, so:

1. Open Settings → **General** → **Grant Access…**
2. Enable the entry in System Settings > Privacy & Security > Accessibility.
   Two rows are named `Badgeify.app` if the original is also installed — ours is the one
   whose icon is the blue tile with a red badge.
3. The banner clears itself within ~2s. If it doesn't, click **Already granted? Relaunch**.
