# DeepListen

**English** | [简体中文](README_CN.md)

> A native macOS player that helps English learners hear more, understand more, and practice difficult lines until they become clear.

[![Release](https://img.shields.io/github/v/release/swiftczz/DeepListen?label=release)](https://github.com/swiftczz/DeepListen/releases/latest)
![Platform](https://img.shields.io/badge/macOS-26.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.3-orange)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

DeepListen is built for people learning English outside an English-speaking environment. When daily exposure is limited, movies, podcasts, interviews, and lessons are valuable—but natural speech is often too fast to study effectively with an ordinary media player.

DeepListen turns your local audio or video and subtitles into a focused listening workspace. Follow speech with word-by-word highlighting, click any sentence to hear it again, slow down difficult passages, loop one sentence, or define an A/B segment for repeated practice.

## Preview

![DeepListen main window](docs/images/deeplisten-main.png)

## Why DeepListen?

### Create your own English environment

Practice with material you actually care about: films, TV shows, podcasts, courses, interviews, or exam recordings. DeepListen works with local files, so your listening practice is not limited to a particular content platform.

### Connect what you hear with what you read

The active subtitle is enlarged and highlighted word by word as the audio plays. This makes it easier to notice connected speech, reductions, rhythm, and words that disappear when native speakers talk naturally.

### Repeat the exact part you missed

Click any subtitle to jump directly to it. Use **Loop Sentence** for one-line repetition, or set A and B points when the difficult passage crosses subtitle boundaries.

### Practice at your own pace

Slow playback down to analyze pronunciation, return to normal speed to test comprehension, and move backward or forward five seconds without breaking concentration.

## A Simple Practice Routine

1. Import an English audio or video file.
2. Put a matching `.srt` or `.vtt` subtitle beside it.
3. Listen once without stopping and identify unclear sentences.
4. Click an unclear sentence and turn on **Loop Sentence**.
5. Follow the word highlighting, imitate the pronunciation, and repeat until the sentence sounds clear.
6. Turn off the loop and continue listening in context.

This workflow works well for intensive listening, shadowing preparation, pronunciation awareness, and IELTS or other English listening practice.

## Features for Listening Practice

### Interactive Subtitles

- Focused current-sentence view or full transcript context
- Word-by-word highlighting synchronized with playback
- One-click jump to any subtitle sentence
- Automatic transcript following, with easy recovery after manual scrolling
- Stable sentence transitions that keep the completed line highlighted until the next line begins
- Automatic cleanup of common subtitle markup
- UTF-8, UTF-16, GB18030, and ISO-Latin1 subtitle support

Standard subtitle files usually provide timing for each sentence rather than each word. DeepListen estimates word progress across the sentence duration to provide a useful visual listening guide.

### Repetition Tools

- **Loop Sentence** automatically uses the active subtitle's start and end times
- Clicking another subtitle moves the sentence loop to that line
- Manual A/B markers for phrases or passages that cross subtitle boundaries
- Visible A/B range and timestamps
- Single-track repeat and sequence playback modes

### Playback Controls

- Playback speed from 0.25x to 2.0x in 0.25x steps
- Five-second rewind and forward controls
- Precise timeline seeking and hover time preview
- macOS media controls and Now Playing integration
- Automatic restoration of the selected track and last playback position
- Saved speed, playback mode, theme, and subtitle preferences

### Local Media Library

- Import individual files or entire folders
- Recursive folder scanning with hidden-file filtering
- Natural filename sorting and duplicate prevention
- Search, drag-to-reorder, multi-selection removal, and Reveal in Finder
- Supported formats: `mp3` `m4a` `aac` `wav` `aiff` `aif` `caf` `flac` `mp4` `m4v` `mov` `avi` `mkv`

### Native macOS Experience

- SwiftUI interface designed for macOS 26
- Liquid Glass controls and nine theme colors
- Adaptive layout for narrow and wide windows
- Keyboard navigation and VoiceOver support

## Install

1. Download the DMG for your Mac, or choose the universal build, from [Releases](https://github.com/swiftczz/DeepListen/releases/latest).
2. Open the DMG and drag `DeepListen.app` into Applications.
3. On first launch, right-click the app and choose **Open**.

Release builds use ad hoc signing. If Gatekeeper still blocks the app, run:

```bash
xattr -dr com.apple.quarantine /Applications/DeepListen.app
```

## Subtitle Matching

Place the subtitle in the same directory as its media file and use the same base filename:

```text
English Practice/
├── Lesson 01.mp3
├── Lesson 01.srt      ← automatically matched
├── Lesson 02.mp4
└── Lesson 02.vtt      ← automatically matched
```

DeepListen checks for matching subtitles whenever a track loads, so you can import media first and add the subtitle later.

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

## Build from Source

### Requirements

- macOS 26.0 or later
- Swift 6.3 toolchain

### Build and Run

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

### Build Release DMGs

```bash
APP_VERSION=1.0.0 ./script/build_and_run.sh --build-only universal --sign --dmg
APP_VERSION=1.0.0 ./script/build_and_run.sh --build-only arm64     --sign --dmg
APP_VERSION=1.0.0 ./script/build_and_run.sh --build-only x86_64    --sign --dmg
```

- `--build-only <arch>` builds `universal`, `arm64`, or `x86_64` in release configuration
- `--sign` applies an ad hoc signature to the app
- `--dmg` writes `DeepListen-<arch>-<version>.dmg` to `dist/`
- `APP_VERSION` is written to `Info.plist` and the DMG filename; if omitted, the latest Git tag or `0.0.0-dev` is used

## Tech Stack

- **SwiftUI** — interface and interaction
- **AVFoundation** — media playback and precise seeking
- **MediaPlayer** — system media controls and Now Playing information
- **Observation** — shared application state
- **Swift Package Manager** — builds and dependency management

## Project Structure

```text
DeepListen/
├── .github/workflows/      # release automation
├── docs/images/            # README assets
├── Resources/              # app icon
├── script/                 # build, run, and packaging scripts
├── Sources/DeepListen/
│   ├── App/                # app entry point and commands
│   ├── Models/             # tracks, subtitles, playback, and theme models
│   ├── Services/           # playback, media discovery, and system integration
│   ├── Stores/             # player state and media library
│   ├── Support/            # subtitle parsing and time formatting
│   └── Views/              # SwiftUI views
├── README.md               # English documentation
├── README_CN.md            # Simplified Chinese documentation
└── Package.swift
```

## License

Copyright 2026 chengzhong.

Licensed under the [Apache License 2.0](LICENSE).
