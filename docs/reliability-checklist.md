# Reliability Checklist

Last updated: April 21, 2026

This is the current release-quality bar for Sony Audio `1.0.0` and later. The goal is not just "works once on my machine," but "behaves predictably enough that we can trust it."

## Stable Release Bar

Before calling any build stable, we should be able to say yes to all of these:

- The XM6 is already connected in macOS, and the app shows it correctly on launch.
- Opening Sony's control channel does not force a false disconnect or tear down the Mac's audio connection.
- Repeated `Noise Cancelling` / `Ambient Sound` / `Off` switching stays responsive.
- The main window does not behave worse than the menu bar for the same control actions.
- Battery either populates within a reasonable window or clearly remains in a syncing state without breaking the rest of the app.
- If the Sony control channel goes stale while macOS still owns the headset, the app recovers cleanly without requiring a re-pair.
- Multipoint interference fails clearly and recoverably instead of leaving dead controls behind.

## Manual Soak Test

Run this against a real `WH-1000XM6` before shipping a release build.

### 1. Cold launch with XM6 already connected in macOS

- Connect the headset to the Mac in Bluetooth settings first.
- Launch the app fresh.
- Confirm the headset name appears immediately instead of a fake disconnected state.
- Confirm the app offers `Open Control` or `Open Control Channel` instead of implying the headset is absent.

### 2. Open the Sony control channel

- Open the control channel once from the main app.
- Confirm the app remains usable after the control channel opens.
- Confirm macOS audio stays connected throughout.

### 3. Repeated noise-control switching

- Switch between `Noise Cancelling`, `Ambient Sound`, and `Off` at least 10 times from the main window.
- Repeat the same test from the menu bar.
- Confirm buttons remain clickable across the whole pill, not just the text.
- Confirm the app does not become choppy or leave the controls dead.

### 4. Battery recovery

- Leave the control channel open for at least 60 seconds.
- Confirm battery either appears or keeps the rest of the app responsive while it remains `Unknown`.
- If battery stays unknown, use `Copy Diagnostics` and note whether controls still work normally.

### 5. Close and reopen control

- Close the Sony control channel while leaving the headset connected in macOS.
- Confirm the app still shows the headset as connected in macOS.
- Reopen control and confirm the app returns to a usable state without needing to re-pair.

### 6. Multipoint sanity check

- If multipoint is enabled, bring a second device nearby.
- Confirm the app either keeps working or fails with a recoverable message.
- If the second device steals the headset, confirm the app can recover after the headset returns to the Mac.

## If Anything Fails

Capture evidence before retrying too much.

1. Use `Copy Diagnostics` in the main window or menu bar.
2. Note the exact action that caused the failure.
3. If the issue looks transport-related, capture a Terminal log too:

```bash
cd '/path/to/xm6-macos-controller'
env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache swift run SonyMacApp 2>&1 | tee /tmp/sony-xm6-connect.log
```

4. Attach the diagnostics report and, if available, the `[SonyRFCOMMTransport]` lines to the GitHub issue.

## Practical Rule

If a build still needs excuses, it is not ready for release. The checklist exists so we can replace guesswork with evidence and ship only when the app has earned trust.
