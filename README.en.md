# DeepListen

[简体中文](README.md) | **English**

A native macOS player designed for focused English listening practice. Import local audio, video, and matching subtitles, then study with word-by-word highlighting, full transcripts, speed control, and A/B looping.

[![Release](https://img.shields.io/github/v/release/swiftczz/DeepListen?label=release)](https://github.com/swiftczz/DeepListen/releases/latest)
![Platform](https://img.shields.io/badge/macOS-26.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.3-orange)

## Preview

![DeepListen main window](docs/images/deeplisten-main.png)

## Highlights

### Media Library

- Drop in files or folders, or open audio and video from the toolbar or Finder
- Recursively scans folders, skips hidden files, and sorts results naturally by filename
- Supports drag-to-reorder, search, multi-selection removal, and Reveal in Finder
- Deduplicates media and persists the library, manual order, durations, and selected track
- Supported formats: `mp3` `m4a` `aac` `wav` `aiff` `aif` `caf` `flac` `mp4` `m4v` `mov` `avi` `mkv`

### Subtitle Practice

- Automatically matches `.srt` / `.SRT` or `.vtt` / `.VTT` subtitles with the **same base filename** as the media
- Supports UTF-8, UTF-16, GB18030, and ISO-Latin1 encodings
- Removes HTML tags and sorts cues by timestamp
- Highlights the current cue word by word; when a subtitle has only cue-level timing, progress is estimated across the cue duration
- Switches between a focused current-cue view and full transcript context; click any cue to jump to it
- Automatically follows the active cue, with one-click resume after manual scrolling

### Playback

- Play or pause, skip backward or forward 5 seconds, scrub precisely, and preview time on timeline hover
- Speed control from 0.25x to 2.0x in 0.25x steps
- Sequence and single-track repeat modes, with saved speed and playback-mode preferences
- Supports macOS media controls, previous or next track, and 5-second skip commands

### A/B Loop Practice

- Set A and B at the current playback position
- See markers and the highlighted loop range on the timeline
- Automatically return to A at the end of the segment, or clear the loop at any time

### Native Interface

- 9 theme colors: system, blue, purple, pink, red, orange, yellow, green, and graphite
- Persists theme and subtitle display preferences
- Adapts to narrow windows and automatically collapses the sidebar when space is limited
- Designed for VoiceOver, keyboard navigation, and macOS Liquid Glass

## Install

1. Download the DMG for your architecture, or the universal build, from [Releases](https://github.com/swiftczz/DeepListen/releases/latest).
2. Open the DMG and drag `DeepListen.app` into Applications.
3. On first launch, right-click the app and choose **Open**.

Release builds use ad hoc signing. If Gatekeeper still blocks the app, run:

```bash
xattr -dr com.apple.quarantine /Applications/DeepListen.app
```

## Quick Start

1. Click `+` in the toolbar, or drop media files or folders into the window.
2. For subtitles, place the subtitle beside the media and give it the same base filename.
3. Select a track and practice with subtitles, speed control, and A/B looping.

## Keyboard Shortcuts

| Shortcut | Action |
| --- | --- |
| `Space` | Play / Pause |
| `←` | Rewind 5 seconds |
| `→` | Forward 5 seconds |
| `⌘⇧←` | Previous track |
| `⌘⇧→` | Next track |
| `⌘⌥←` | Rewind 5 seconds |
| `⌘⌥→` | Forward 5 seconds |
| `⌘⌥A` | Set A point |
| `⌘⌥B` | Set B point |
| `⌘⌥Esc` | Clear A/B segment |
| `⌘⌥S` | Show / hide subtitles |

Unmodified playback shortcuts are disabled while editing the search field or another text input.

## Subtitle Matching

Subtitle files must be in the same directory as their media and use the same base filename:

```text
My Material/
├── Lesson 01.mp3
├── Lesson 01.srt      ← auto-matched
├── Lesson 02.mp4
└── Lesson 02.vtt      ← auto-matched
```

The app searches for subtitles whenever a track loads, so you can import media first and add its subtitle later.

## Build from Source

### Requirements

- macOS 26.0 or later
- Swift 6.3 toolchain

### Build and Run

```bash
git clone https://github.com/swiftczz/DeepListen.git
cd DeepListen
swift build
swift run DeepListen
```

To create an `.app`, register it with LaunchServices, and launch it, use:

```bash
./script/build_and_run.sh
```

Additional development modes:

| Command | Purpose |
| --- | --- |
| `./script/build_and_run.sh --debug` | Build and debug with LLDB |
| `./script/build_and_run.sh --logs` | Launch and stream process logs |
| `./script/build_and_run.sh --telemetry` | Launch and stream app subsystem logs |
| `./script/build_and_run.sh --verify` | Launch and verify that the process stays alive |

### Build a DMG

```bash
APP_VERSION=0.8.0 ./script/build_and_run.sh --build-only universal --sign --dmg
APP_VERSION=0.8.0 ./script/build_and_run.sh --build-only arm64     --sign --dmg
APP_VERSION=0.8.0 ./script/build_and_run.sh --build-only x86_64    --sign --dmg
```

- `--build-only <arch>`: builds `universal`, `arm64`, or `x86_64` in release configuration
- `--sign`: applies an ad hoc signature to the `.app`
- `--dmg`: writes `DeepListen-<arch>-<version>.dmg` to `dist/`
- `APP_VERSION`: is written to `Info.plist` and the DMG filename; if unset, the latest Git tag or `0.0.0-dev` is used

## Automated Releases

Pushing a `v*` tag triggers the [Release workflow](.github/workflows/release.yml):

```bash
git tag -a vX.Y.Z -m "DeepListen vX.Y.Z"
git push origin vX.Y.Z
```

The workflow builds universal, arm64, and x86_64 DMGs on a `macos-26` runner, generates release notes, and creates a GitHub Release. A manually dispatched run uploads build artifacts without creating a Release.

## Default Audio Directory

When the library is empty, the app tries to import playable media from:

1. `Resources/DefaultAudio/` inside the app bundle
2. `备考资料/官方材料/音频/`, searched up to 8 parent directories from the current working directory

## Tech Stack

- **SwiftUI**: interface and interaction
- **AVFoundation**: media playback and duration loading
- **MediaPlayer**: system media controls and Now Playing information
- **Observation**: `@Observable` state management
- **Swift Package Manager**: builds and dependency management

## Project Structure

```text
DeepListen/
├── .github/workflows/
│   └── release.yml          # tag-triggered DMG release workflow
├── docs/images/             # README image assets
├── Resources/
│   └── AppIcon.icns
├── script/
│   ├── build_and_run.sh     # local run and packaging
│   └── generate_changelog.sh
├── Sources/DeepListen/
│   ├── App/                 # app entry point and menu commands
│   ├── Models/              # tracks, subtitles, playback mode, and theme
│   ├── Services/            # media discovery, Finder, and system media integration
│   ├── Stores/              # playback state and media library
│   ├── Support/             # subtitle parsing and time formatting
│   └── Views/               # SwiftUI views
└── Package.swift
```

## License

This project is currently intended for personal study and does not specify an open-source license.
