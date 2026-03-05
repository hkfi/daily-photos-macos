# Daily Photos

A macOS menu bar app that automatically imports photos from your Apple Photos library into an [Obsidian](https://obsidian.md) vault.

## Features

- **Auto-import** — Periodically checks for new photos and copies them to your vault
- **Configurable intervals** — 5 min to 2 hours
- **HEIC to JPEG conversion** — Optional, on by default
- **Daily note integration** — Appends `![[photo]]` embeds to your Obsidian daily note
- **Date-based folders** — Organize photos into `Photos/2025-01-15/` subfolders (customizable with `{{date}}` template)
- **Duplicate tracking** — Remembers imported photos so they're never copied twice
- **iCloud support** — Downloads photos from iCloud when needed
- **Auto-update** — Checks GitHub for new releases and can update itself in-place

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode Command Line Tools (`xcode-select --install`)

## Install

```bash
git clone https://github.com/hkfi/daily-photos-macos.git
cd daily-photos-macos
make install
```

This builds the app and copies it to `~/Applications/DailyPhotos.app`.

To launch on login: **System Settings > General > Login Items > add DailyPhotos**

## Usage

1. Click the photo icon in the menu bar
2. On first launch, you'll be prompted to select your Obsidian vault folder
3. Configure import settings (interval, JPEG conversion, daily note) in **Settings**
4. The app runs in the background and imports new photos automatically

## Updating

The app checks for updates automatically. When a new version is available, an update banner appears in the menu bar popover — click **Install & Relaunch** to update in place.

You can also check manually via the menu bar or **Settings > About > Check for Updates**.

## Build

```bash
make build    # Build only
make run      # Build and launch
make install  # Build and install to ~/Applications
make clean    # Remove build artifacts
```

If [xcodegen](https://github.com/yonaskolb/XcodeGen) is installed (`brew install xcodegen`), the build uses `xcodebuild` with the generated Xcode project. Otherwise it falls back to direct `swiftc` compilation.

## Releasing

To publish a new version:

1. Update the version in `project.yml` (`MARKETING_VERSION`) and `Resources/Info.plist` (`CFBundleShortVersionString`)
2. Commit and push
3. Tag and push:
   ```bash
   make release VERSION=0.2.0
   ```

GitHub Actions will build the app and create a release with `DailyPhotos.app.zip` attached. Users with the app installed will be notified of the update automatically.

## Project Structure

```
Sources/
  DailyPhotosApp.swift   # App entry point (MenuBarExtra)
  AppState.swift          # Central state management
  MenuBarView.swift       # Menu bar popover UI
  SettingsView.swift      # Settings window
  PhotoImporter.swift     # PhotoKit wrapper (fetch & export)
  ImportTracker.swift     # Tracks imported photo IDs (JSON persistence)
  Updater.swift           # GitHub-based auto-updater
Resources/
  Info.plist              # App metadata & permissions
  DailyPhotos.entitlements
```

## License

MIT
