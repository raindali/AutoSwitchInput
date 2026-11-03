# AutoSwitchInput

> A tiny menu-bar utility that auto-switches your macOS input source per app.

---

## Introduction

AutoSwitchInput is a native macOS menu-bar app. As you switch between foreground apps, it automatically selects the input source defined by your rules — for example, terminal apps always switch to English (ABC), while chat apps like WeChat switch to Pinyin. No more toggling input methods by hand.

---

## Features

- **Per-app auto switch** — Watches the active app (80ms debounce) and applies the matching rule.
- **Rule-based** — Each rule maps a bundle ID to an input source, with a live dropdown picker.
- **Sensible defaults** — Seeded on first launch: Terminal/iTerm2/VS Code/Xcode/Warp → ABC; WeChat → Pinyin.
- **Menu-bar background agent** — No Dock icon; a persistent menu-bar item only. Launches and stays resident in the background; click the icon to open the window anytime.
- **Liquid Glass UI** — Native Liquid Glass on macOS 26 (Tahoe); gracefully falls back to a thin-material look on older macOS.
- **Deep-gray theme** — A consistent deep-gray accent and app icon, replacing the default blue.
- **Launch at login** — Toggle "launch at login" in General settings.
- **⌘W to close** — Closing the window keeps the app resident in the menu bar; click the menu-bar icon to reopen.

---

## Requirements

- macOS 14.0 or later
- Apple Silicon (arm64)
- Input switching requires system authorization; you may need to grant **Input Monitoring / Accessibility** permission in System Settings on first use.
- Building from source requires the **Xcode Command Line Tools**.

---

## Installation

**Option A: Build from source (recommended)**

```bash
cd AutoSwitchInput
bash build.sh
open /Applications/AutoSwitchInput.app
```

`build.sh` compiles an arm64 binary, packages it into a `.app`, ad-hoc signs it, and auto-deploys to `/Applications`.

**Option B: Build only (no install)**

```bash
cd AutoSwitchInput
bash build.sh --no-install
open AutoSwitchInput.app
```

> If macOS blocks the unsigned app: System Settings › Privacy & Security › Allow Anyway.

**Run the tests**

```bash
swift test
```

**Releasing (maintainers)**

See [docs/RELEASING.md](./docs/RELEASING.md) for signing, notarization and CI
secrets — including **what information becomes public** with a signed build.
Run `./scripts/release-check.sh` before tagging.

No paid developer account is required: with no secrets the build is ad-hoc; with a
self-signed certificate (`./scripts/make-self-signed-cert.sh`) the signing identity
stays stable across updates, so users don't have to re-grant permissions.

---

## Usage

1. Launches quietly in the background (persistent menu-bar icon); click the icon to open the window. After closing, the app stays resident.
2. **General**
   - Enable auto switch — master toggle.
   - Default input source — fallback when no rule matches.
   - Launch at login.
3. **App rules**
   - One row per app; pick the target input source from the dropdown; click the trash to remove.
   - Click *Add Rule* to pick from currently running apps.
4. Switch apps and watch the input source follow your rules.

---

## Preview

> The image below is a mockup matching the actual UI; real captures live in [docs/screenshots](./docs/screenshots).

![AutoSwitchInput main window](./docs/screenshots/main-window.png)

---

## Project Structure

```
AutoSwitchInput/
├── Package.swift                     # SwiftPM: Core / UI / two executables
├── Sources/
│   ├── AutoSwitchInputCore/          # Pure logic (no SwiftUI)
│   │   ├── Models.swift              # AppRule, run mode
│   │   ├── RuleStore.swift           # Persistence + cross-process sync + login item
│   │   ├── InputMethodManager.swift  # Carbon TIS wrapper and filtering
│   │   ├── AppMonitor.swift          # Foreground app watching with debounce
│   │   ├── Localization.swift        # L10n helper
│   │   └── Log.swift                 # os.Logger categories
│   ├── AutoSwitchInputUI/            # SwiftUI settings UI
│   │   ├── SettingsView.swift        # Main UI + header status (Liquid Glass)
│   │   ├── RuleRow.swift             # Single rule row
│   │   ├── AddRuleSheet.swift        # Add-rule sheet
│   │   ├── AutoInputMenu.swift       # Custom input-source dropdown
│   │   └── Design.swift              # Design tokens and LiquidGlass modifier
│   ├── AutoSwitchInput/              # Menu-bar process (does not link SwiftUI)
│   │   ├── main.swift
│   │   └── AppDelegate.swift         # Status item, context menu, launches settings
│   └── AutoSwitchInputSettings/      # Settings process (quits when its window closes)
│       ├── main.swift
│       └── SettingsAppDelegate.swift
├── Tests/AutoSwitchInputCoreTests/   # Unit tests (swift test)
├── Resources/
│   ├── en.lproj/Localizable.strings      # English strings
│   ├── zh-Hans.lproj/Localizable.strings # Simplified Chinese strings
│   ├── Info.plist
│   ├── AppIcon.icns            # Deep-gray keyboard app icon
│   └── icon_src/gen_dock_icon.swift  # Icon generation script
├── scripts/release-check.sh    # Pre-release checks (secrets / privacy / architecture)
├── docs/RELEASING.md           # Release flow and privacy notes
├── build.sh                    # Package .app + deploy script
├── LICENSE                     # GPLv3
├── README.md                   # Chinese documentation
└── README_EN.md                # English documentation
```

---

## Tech Stack

Swift 6 language mode · SwiftPM · SwiftUI · AppKit · Carbon TIS API · XCTest · en / zh-Hans localization · `os.Logger` · ad-hoc signing · `SMAppService.mainApp` login item.

---

## License

Licensed under the **GNU General Public License v3.0 (GPLv3)**. See [LICENSE](./LICENSE).
