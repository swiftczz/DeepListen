# DeepListen

[简体中文](README.md) | **English**

A macOS player built for focused English listening practice. Import any subtitled audio or video and drill your listening with A/B looping, speed control, full transcripts, and context display.

![Platform](https://img.shields.io/badge/platform-macOS%2026.0-blue)
![Language](https://img.shields.io/badge/language-Swift-orange)
![Version](https://img.shields.io/badge/version-0.1.0-green)

## Features

### Library

- Drop in files or folders, or open audio/video from Finder
- Recursive folder scanning, sorted by filename
- Supported formats: `mp3` `m4a` `aac` `wav` `aiff` `aif` `caf` `flac` `mp4` `m4v` `mov` `avi` `mkv`
- Library is persisted and restored automatically on next launch
- Sidebar search, right-click "Reveal in Finder", remove from list

### Subtitles

- Auto-matches subtitle files with the **same name** as the media (`.srt` / `.vtt`, case-insensitive)
- Handles UTF-8 / UTF-16 / ISO-Latin1 encodings
- Strips HTML tags from subtitle text
- Two display modes:
  - **Current**: highlights the active cue, with optional previous / next context
  - **Transcript**: full subtitle list — click any line to jump
- One-toggle show / hide subtitles and context

### Playback

- Play / pause, skip ±5 seconds, precise scrubbing
- Speed control: 0.25x – 2.0x in 0.25x steps
- Playback modes: sequence / single loop

### A/B Loop Practice

- Set A and B points, marked and highlighted on the timeline
- Auto-loops back to A when the segment ends
- One-tap clear

### Appearance

- 9 theme colors: system, blue, purple, pink, red, orange, yellow, green, graphite
- Theme persists across launches
- Adaptive layout for narrow windows with auto-collapsing sidebar

## Keyboard Shortcuts

| Shortcut | Action |
| --- | --- |
| `Space` | Play / Pause |
| `P` | Previous track |
| `N` | Next track |
| `←` | Rewind 5s |
| `→` | Forward 5s |
| `A` | Set A point |
| `B` | Set B point |
| `Esc` | Clear A/B segment |
| `S` | Toggle subtitles |

## Subtitle Matching

Place subtitle files in the same directory as the media, using the **same base filename** — the app loads them automatically:

```
My Material/
├── Lesson 01.mp3
├── Lesson 01.srt      ← auto-matched
├── Lesson 02.mp4
└── Lesson 02.vtt      ← auto-matched
```

## Build from Source

### Requirements

- macOS 26.0 or later
- Swift 6.3 toolchain

### Build & Run

```bash
./script/build_and_run.sh            # build and launch
./script/build_and_run.sh --debug    # build and debug in lldb
./script/build_and_run.sh --logs     # launch and stream process logs
./script/build_and_run.sh --telemetry# launch and stream subsystem logs
./script/build_and_run.sh --verify   # launch and verify the process is alive
```

The script runs `swift build`, packages the output into `dist/DeepListen.app`, and registers it with LaunchServices so you can double-click audio/video files in Finder to open them in DeepListen.

To compile without packaging:

```bash
swift build
```

## Default Audio Directory

On launch, if the library is empty the app tries to auto-load default audio from:

1. `Resources/DefaultAudio/` inside the app bundle
2. `备考资料/官方材料/音频/` searched up to 8 parent directories from the working directory

If found, playable media inside is imported automatically.

## Tech Stack

- **SwiftUI** — entire UI layer
- **AVFoundation** — audio/video playback
- **Observation** — `@Observable` state management
- **Swift Package Manager** — dependencies and build

## Project Structure

```
DeepListen/
├── Package.swift
├── Resources/
│   └── AppIcon.icns
├── script/
│   └── build_and_run.sh
└── Sources/DeepListen/
    ├── App/            # @main entry and menu commands
    ├── Models/         # track, subtitle, playback mode, theme color
    ├── Stores/         # PlayerStore playback state
    ├── Services/       # system capabilities like Finder reveal
    ├── Support/        # subtitle parsing, time formatting
    └── Views/          # SwiftUI views
```

## License

For personal study use; no open-source license specified yet.
