# StepAway

English | [中文](README.zh.md)

A macOS menu bar app that runs work/break cycles and knows when to stay quiet.
Breaks are suspended automatically while you are idle, in a call, sharing your
screen, inside a fullscreen or focus app, or outside office hours — so the
reminder only shows up when stepping away is actually possible.

[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey.svg)](#requirements)

## Features

**Timer** — 20 min work, 20 s short break, 5 min long break after every 4 short
breaks. All durations are configurable. The menu bar shows the remaining time
(`☕` while breaking, `⏸` when paused manually, `◐` when paused by a detector).

**Break overlay** — covers every display and joins fullscreen Spaces instead of
pulling you out of them. Rendered by Metal shaders (aurora / plasma / rays) with
a gradient fallback when no GPU is available. The overlay is excluded from
screen recordings by default via `NSWindow.sharingType = .none`.

**Pre-break HUD** — a 60 s heads-up before the overlay appears, so you can get to
a stopping point.

**Auto-pause** — detectors are polled every 5 s and a verdict must persist for
two consecutive polls before the timer pauses (and two clean polls before it
resumes), so one stray window cannot flap the timer.

| Detector | Triggers when |
| --- | --- |
| Idle | No input for 5 min — you already left |
| Meeting / screen sharing | A camera or mic is in use **and** a known meeting client is running |
| Fullscreen app | Any non-player app owns a fullscreen window (games, immersive apps) |
| Video playback | A known video player owns a fullscreen window |
| Calendar event | A non-all-day event is in progress (requires calendar access) |
| Office hours | Outside the configured working window (supports overnight ranges) |
| Deep focus apps | An app you marked as a focus app is frontmost (opt-in) |

Calendar, screen-sharing, fullscreen, video and office-hours detectors are
individually toggleable; office hours and deep focus are off by default. Apps can
be excluded through the ignore list.

**Guard rails** — skipping and postponing are rationed: 3 skips and 30 min of
postponement per day, reset at local midnight. The menu bar shows what is left.
System sleep pauses the timer and the remaining time is adjusted on wake. A second
launch exits instead of starting another instance, and the bundled app brings the
running one to the front.

**Everything is local** — no network access. Settings live in `UserDefaults`,
break statistics and daily quotas in `~/Library/Application Support/StepAway/`
(`stats.json`, `quotas.json`).

## Requirements

- macOS 13 Ventura or later
- Swift 5.10 toolchain (Xcode 15+ or the standalone Swift toolchain)

## Build and run

```sh
swift build                # compile
swift run StepAway         # run as a bare process
swift run StepAway --demo  # 8 s work / 6 s break cycles; demo settings are not saved
```

The demo still records break statistics. To keep them out of your real stats file:

```sh
STEPAWAY_STATS_PATH=/tmp/stepaway-demo.json swift run StepAway --demo
```

To build a launchable app bundle:

```sh
./Scripts/make-app.sh      # release build, bundles and ad-hoc signs build/StepAway.app
open build/StepAway.app
```

Use the bundled app for daily use: it sets `LSUIElement` (menu bar only) and
carries `NSCalendarsUsageDescription`, which EventKit requires before macOS will
show the calendar permission prompt.

## Usage

Launch the app and open `设置…` (⌘,) from the menu bar item to configure it.

| Menu item | Shortcut | Notes |
| --- | --- | --- |
| Pause / Resume | ⌘P | Manual pause; resume shows the detected reason |
| Start break now | ⌘B | Skips the rest of the work interval |
| Skip break | ⌘S | Available only during a break, uses one daily skip |
| Postpone | — | Available only during work, uses the daily postpone budget |
| 忽略当前应用 | — | Excludes the frontmost app from detector verdicts |
| 标记当前应用为专注应用 | — | Adds the frontmost app to the focus list (when enabled) |
| Quit | ⌘Q | |

## Development

```sh
swift run StepAway --selftest   # deterministic checks; exit code = number of failures
```

The self-test covers the timer state machine, detectors, quota/stats persistence,
instance locking and Metal shader availability. It needs no UI, so it can run
unattended — but the shader checks require a working GPU and fail on headless
machines.

Layout:

- `Sources/StepAway/Core` — timer engine, settings, stats/quota stores, detectors protocol
- `Sources/StepAway/Detectors` — one type per auto-pause signal
- `Sources/StepAway/UI` — menu bar item, break overlay, pre-break HUD, settings window
- `Scripts/make-app.sh` — app bundle packaging

Detectors are kept cheap and side-effect free: they run on a short poll interval
and only report a verdict, never change state themselves.

Environment overrides (mainly for testing and local captures):

- `STEPAWAY_STATS_PATH`, `STEPAWAY_QUOTA_PATH` — relocate the JSON stores
- `STEPAWAY_SHOW_IN_CAPTURE=1` — let the overlay appear in screen recordings

## Limitations

- The build is ad-hoc signed, not notarized; Gatekeeper may require a manual
  confirmation on first launch.
- Screen-sharing detection is a heuristic: macOS exposes no public query for
  "another app is capturing the screen", so it watches for an active camera or
  microphone session combined with a running meeting client.
- The UI is currently Chinese-only, and the bundle identifier
  (`com.example.stepaway`) is a placeholder to replace before distributing a build.

## Contributing

Issues and pull requests are welcome. Please run `swift build` and
`swift run StepAway --selftest` before submitting, and keep detector logic in
`Sources/StepAway/Detectors` free of side effects so it stays testable.

## License

[Apache License 2.0](LICENSE)
