# Release notes

## 0.9.0-public-preview.1 — first public preview

First public source preview of Display HUD, a free macOS menu-bar utility for
precise brightness and volume control from the media keys. MIT licensed
(copyright TENEDOR JP).

- Bundle version: `0.9.0 (901)`. The `901` build number distinguishes this
  public preview line from earlier private builds; the release tag is
  `v0.9.0-public-preview.1`.
- Brightness keys drive BetterDisplay combined brightness on an exact
  0.5-percentage-point grid, targeting the display under the pointer.
- Volume keys drive CoreAudio default-output volume on the same 0.5-point
  grid, without requiring BetterDisplay; the mute key toggles CoreAudio mute.
- A first press from an off-grid value snaps to the next grid point in the
  pressed direction (at most 0.5 points); the app never writes a value except
  in response to a key press.
- Passive 318×88 HUD, hold-to-repeat, fail-open pass-through for anything
  unavailable, and recovery across login, lock, sleep/wake, Space, display,
  and output-device transitions.
- Launch at Login is strictly opt-in through the menu-bar toggle. The app
  never registers itself.
- Includes the headless unit-test suite. Window-backed presenter tests are
  opt-in (`DISPLAY_HUD_WINDOW_TESTS=1`); live hardware and input-injection
  tests are intentionally not shipped.

BetterDisplay is required for brightness control. It is installed and
licensed separately and is not bundled here; see its current
[free and Pro features guide](https://betterdisplay.pro/guide/licensing/free-and-pro-features/).

### Distribution honesty

- Supported: macOS 15+, Apple silicon (arm64) only.
- These builds are **ad-hoc signed only** — not notarized, not Developer ID
  signed. First launch needs the Open Anyway approval in
  System Settings → Privacy & Security (see [INSTALL.md](INSTALL.md)).
- This is a preview, not a 1.0 stable release.

### Known limitations

- Developed and used on macOS 26 (Apple silicon); macOS 15 is the declared
  minimum but has not been tested.
- Brightness has been tested only with BetterDisplay 4.3.5, through its
  legacy `com.betterdisplay.BetterDisplay.request`/`.response` distributed
  notifications; future BetterDisplay versions may change them. These are
  unauthenticated local notifications that other apps in the same session
  can observe.
- Volume and mute apply only to outputs whose volume or mute macOS reports
  as settable; otherwise the keys pass through.
- Ad-hoc builds have no stable signing identity: after every update,
  approve again under Privacy & Security → Open Anyway and re-enable
  Display HUD under Privacy & Security → Accessibility.
- Launch at Login has not been tested with ad-hoc builds; a registration
  error appears in the menu.
- The release binary was rebuilt from this source with Xcode 27.0 and has
  not been separately acceptance-tested on hardware.

### Artifacts

- `Display-HUD-0.9.0-public-preview.1-arm64.zip` — ad-hoc signed app
- `Display-HUD-0.9.0-public-preview.1-source.tar.gz` — exact committed source
- `SHA256SUMS.txt` — SHA-256 checksums for both archives
