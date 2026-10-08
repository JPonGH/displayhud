# Security Policy

## Supported versions

Only the latest public preview release is supported. Older preview builds
should be replaced rather than patched.

## Reporting a vulnerability

Open a private security advisory on GitHub for this repository, or open a
regular issue with no exploit details and ask for a private channel. Please
do not publish exploit details before a fix is available.

Include the app version (from the bundle `Info.plist`), the macOS version,
and steps to reproduce. Reports that require disabling system security
features to reproduce are still welcome — say so explicitly.

## Scope notes

- Display HUD requests Accessibility access only for its media-key event tap,
  and requests no network, camera, microphone, or screen-capture permissions.
- Preview builds are ad-hoc signed, not notarized or Developer ID signed.
  Unexpected network connections, helper installations, or permission prompts
  beyond Accessibility are not normal behavior — please report them.
