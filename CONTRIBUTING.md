# Contributing to Display HUD

Thanks for your interest. This is a small, stability-focused utility, so
changes stay narrow and behavior-preserving.

## Ground rules

- Keep the app a single local process: no network code, telemetry, helpers,
  daemons, audio taps, or screen capture.
- Preserve fail-open behavior: any key Display HUD cannot safely control must
  reach macOS unchanged.
- Never write brightness or volume except in direct response to a user key
  press. Startup, readiness probes, and lifecycle recovery must be read-only.
- Launch at Login stays strictly opt-in through the menu toggle. Never
  register it automatically.
- Match the existing Swift style (Swift 6, `swift-tools-version: 6.2`) and
  keep new code covered by headless tests where practical.

## Workflow

1. Open an issue describing the behavior change and why it is needed.
2. Keep the diff small and focused; one behavior per pull request.
3. Run `swift build` and `swift test` before pushing. CI runs the same on
   the `macos-26` runner.
4. Do not include machine-specific paths, signing identities, screenshots of
   personal setups, or hardware baselines in issues or pull requests.

## Tests

- `swift test` runs the default headless suite: fixed-point stepping,
  control-engine lanes, capture sessions, backend adapters against fakes, and
  off-screen HUD rendering. It creates no windows and writes no hardware
  state.
- Window-backed presenter tests are opt-in:
  `DISPLAY_HUD_WINDOW_TESTS=1 swift test`. They briefly show passive HUD
  panels; do not run them when a clean screen matters.
- This repository intentionally contains no live hardware or input-injection
  tests.

## License

Contributions are accepted under the MIT license in [LICENSE](LICENSE).
