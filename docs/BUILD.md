# Building and packaging Display HUD

Prerequisites: macOS 15 or later on Apple silicon, with Xcode 26+ (Swift
6.2+) installed. No third-party dependencies, signing identities, or Apple
Developer account are needed.

All scripts are portable: they take no identity or path arguments, install
nothing, launch nothing, and hard-code no personal paths. Build output goes
to a temporary directory unless `DISPLAY_HUD_BUILD_ROOT` is set.

## Build the app

```sh
./scripts/build-app.sh
```

This compiles the Swift package for arm64 release, assembles
`Display HUD.app` (executable, `Info.plist`, generated icon), strips local
symbol-table debug info from the bundled executable, ad-hoc signs it,
strictly verifies the signature, and prints the resulting app path.

The build uses `swift build --build-system native`: the default swiftbuild
engine mis-stamps `LC_BUILD_VERSION` with sdk 15.0 on current toolchains,
which changes AppKit compatibility behavior, while the native engine stamps
the current SDK and keeps the macOS 15.0 minimum. `package-release.sh`
refuses to package a binary stamped below sdk 26.

The build is **ad-hoc signed only** (`codesign --sign -`). It is **not
notarized and not Developer ID signed**. Do not expect it to pass Gatekeeper
without the first-open approval described in [INSTALL.md](INSTALL.md).

## Run the tests

```sh
swift test
```

The default suite is headless: fixed-point stepping, control-engine lanes,
capture sessions, backend adapters against in-memory fakes, in-process event
routing, and off-screen HUD rendering. It creates no windows and writes no
display, audio, or input state.

Window-backed presenter tests exist but are opt-in because they briefly show
passive HUD panels:

```sh
DISPLAY_HUD_WINDOW_TESTS=1 swift test
```

This repository intentionally contains no live hardware or input-injection
tests. Thread Sanitizer can be used for an extra pass:

```sh
swift test --sanitize=thread
```

## Package a release

```sh
./scripts/package-release.sh [VERSION]
```

`VERSION` defaults to `0.9.0-public-preview.1`. The script rebuilds the app,
then writes to `dist/release-$VERSION/`:

- `Display-HUD-$VERSION-arm64.zip` — the ad-hoc signed arm64 app archive
- `Display-HUD-$VERSION-source.tar.gz` — the exact committed source
  (`git archive` of `HEAD`, so commit first)
- `SHA256SUMS.txt` — SHA-256 checksums of the two archives

`dist/` is gitignored. Nothing is uploaded anywhere; publishing a release is
a separate manual step.

## Continuous integration

`.github/workflows/build.yml` runs on every push and pull request
(`macos-26` runner): debug build, headless `swift test`, app-bundle build
with ad-hoc signing, and an upload of the resulting bundle as a CI artifact.
Actions are pinned by commit SHA. CI never signs with a Developer ID, never
notarizes, and never publishes a release.
