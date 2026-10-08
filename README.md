# Display HUD

Display HUD is a free, open-source macOS menu-bar utility for precise display
brightness and system-audio control from the media keys. It is a single
accessory process: a menu-bar status item plus a small passive on-screen HUD.
There is no helper app, daemon, network code, or telemetry.

This is a **public preview** (`0.9.0-public-preview.1`). It is not a 1.0 stable
release, and it has not been validated across all Mac hardware. See
[docs/RELEASE-NOTES.md](docs/RELEASE-NOTES.md).

## What it does

- **Brightness keys** (typically F1/F2): adjust the display under the pointer
  in exact 0.5-percentage-point steps through BetterDisplay's combined
  brightness control. The target display is locked for the duration of a hold.
- **Volume keys** (typically F11/F12): adjust the default audio output in
  exact 0.5-percentage-point steps through CoreAudio. Works without
  BetterDisplay, subject to what the active output device supports.
- **Mute key** (typically F10): toggles the normal CoreAudio mute state.
- If a backend reports an off-grid value (for example 37.3%), the first press
  in a direction snaps to the next grid point in that direction
  (37.5% for Up, 37.0% for Down) — never more than 0.5 points, never opposite
  the key. Later presses are exactly 0.5 points. Launching the app never
  writes a value on its own.
- Each press shows a passive 318×88 HUD at the center of the target display
  with the requested value. The HUD never takes focus or intercepts clicks.
- Holding a key repeats after a 250 ms delay, then one step every 60 ms.
- Anything the app cannot safely control fails open: the original media-key
  event is passed through to macOS unchanged.
- The menu-bar menu shows input permission, event-tap, brightness, audio, and
  last-action status, plus an Enabled toggle, a Test HUD action that changes
  no value, and Quit.

## Requirements

- macOS 15 or later, Apple silicon (arm64). Intel Macs are not supported by
  this preview's builds.
- [BetterDisplay](https://betterdisplay.pro), installed separately, for
  brightness control. Display HUD talks to BetterDisplay locally through its
  documented distributed-notification integration. BetterDisplay is **not
  bundled** with Display HUD and is **separately licensed**: use is subject
  to BetterDisplay's license terms — "free" refers to feature access only,
  operations on Pro features remain Pro, and business users must purchase
  Pro after the trial. See BetterDisplay's current
  [free and Pro features guide](https://betterdisplay.pro/guide/licensing/free-and-pro-features/)
  for the exact terms. Volume control uses CoreAudio directly and does not
  need BetterDisplay.
- Accessibility permission for Display HUD, so it can receive media keys
  through a Core Graphics event tap. macOS asks when the app first starts.

## Install

1. Download `Display-HUD-0.9.0-public-preview.1-arm64.zip` from the release
   and verify it against `SHA256SUMS.txt` (see [docs/INSTALL.md](docs/INSTALL.md)).
2. Unzip and move **Display HUD.app** to `/Applications`.
3. Open it from Finder. If macOS blocks the first launch, choose **Done**,
   then approve just this app via **System Settings → Privacy & Security →
   Open Anyway** — that is expected for this ad-hoc signed preview (details in
   [docs/INSTALL.md](docs/INSTALL.md)).
4. Grant Accessibility permission when macOS asks.

These preview builds are **ad-hoc signed only**. They are **not notarized**
and **not Developer ID signed**. See [docs/INSTALL.md](docs/INSTALL.md) for
details, Launch at Login opt-in, and uninstall steps.

## Build from source

```sh
./scripts/build-app.sh        # writes an ad-hoc signed app to a temp dir
./scripts/package-release.sh  # writes ZIP + source archive + SHA256SUMS to dist/
swift test                    # headless unit tests only
```

Details, including the opt-in window-backed HUD tests, are in
[docs/BUILD.md](docs/BUILD.md).

## Privacy and process model

One AppKit process. No network APIs, no telemetry, no sockets, no helper or
login-item executable beyond the app itself, no audio taps, no screen capture.
BetterDisplay communication is local distributed-notification traffic;
CoreAudio access is limited to default-output volume and mute properties;
Accessibility is used only for the media-key event tap. Launch at Login is
strictly opt-in through the menu-bar toggle — the app never registers itself.

## Reuse

Display HUD is MIT licensed (see [LICENSE](LICENSE)). Maintainers of related
tools — including BetterDisplay — are welcome to reuse or integrate any part
of it under the MIT terms. That permission is not an endorsement by, and does
not transfer any ownership to, any other project.

## Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).
