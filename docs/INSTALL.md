# Installing Display HUD (public preview)

Supported configuration: **macOS 15 or later on Apple silicon (arm64)**.
Intel Macs are not supported by this preview's builds, and behavior on
unlisted hardware has not been validated.

## From the release archive

1. Download `Display-HUD-0.9.0-public-preview.1-arm64.zip` and
   `SHA256SUMS.txt` from the release page.
2. Verify the download (run in the folder holding both files):

   ```sh
   shasum -a 256 -c SHA256SUMS.txt
   ```

   Only the two files listed in `SHA256SUMS.txt` are covered; check that both
   report `OK`.
3. Unzip and drag **Display HUD.app** to `/Applications`.
4. Open it from Finder. This preview is **ad-hoc signed only — not notarized
   and not Developer ID signed** — so on first launch macOS may block it as
   coming from an unidentified developer. If so, choose **Done** in the
   blocking dialog, then open **System Settings → Privacy & Security**, find
   the **Open Anyway** option for Display HUD, click it, and confirm. This
   approves just Display HUD; it does not change any system-wide security
   setting. (On macOS 15 and later, Control-click → Open no longer overrides
   the block for unnotarized apps, so use the Open Anyway flow.) Never disable
   Gatekeeper globally or strip the app's quarantine flag to work around this.
5. When macOS asks, grant Display HUD Accessibility permission so it can
   receive media keys. Without it, the menu shows `Input permission: Required`
   and all keys pass through to macOS unchanged.
6. Install and run [BetterDisplay](https://betterdisplay.pro) for brightness
   control. Volume control works without it, subject to the active output
   device's capabilities.

## Launch at Login (opt-in)

Display HUD never registers itself for Launch at Login. To start it
automatically, open its menu-bar menu and turn on **Launch at Login**. macOS
may ask you to approve this in System Settings; follow its prompt. Turn the
same toggle off to unregister.

## Uninstall

1. Quit Display HUD from its menu-bar menu.
2. If Launch at Login was enabled, disable it in the menu first (or remove it
   under System Settings → General → Login Items).
3. Delete `/Applications/Display HUD.app`.
4. Optionally remove the preference: `defaults delete com.jp.DisplayHUD`.

No helper apps, daemons, kernel extensions, or network components are
installed, so nothing else needs cleanup.
