# Connection And UI Fixes

Last updated: April 21, 2026

This page summarizes the connection and responsiveness fixes that landed on the path to the `1.0.0` release after repeated real-headset testing on a WH-1000XM6.

## What Changed

### macOS is now the source of truth

The app now assumes the headset should already be connected in macOS first.

- The app no longer treats a merely paired headset as something it should independently bring online.
- If the XM6 is already connected to the Mac for audio, the app can open Sony's control channel lazily when you actually use a control.
- If the app did not open the underlying macOS Bluetooth connection itself, disconnecting the control channel no longer tears down the Mac's audio connection.
- Status wording now follows the Mac's Bluetooth state, so the app does not label the headset as "disconnected" while macOS still shows it connected.

### Control-channel recovery is more resilient

The Sony control channel can go stale even while the headset remains connected in macOS.

- If a control command hits a timeout but macOS still owns the headset, the app now reopens the Sony control channel once and retries the command.
- Startup refresh remains best-effort instead of forcing an immediate disconnect when one early query is slow.
- Transport diagnostics still log the difference between a settling control channel and a likely multipoint or handoff interruption.

### Bluetooth work no longer runs on the UI thread

The transport now runs on a dedicated Bluetooth run-loop thread instead of the main UI thread.

- This keeps RFCOMM polling and response waits off the main window.
- Main-window interaction should feel noticeably less sticky during repeated control changes.
- The menu bar and main window now use the same lower-friction connection model.

### Battery refresh is now gentle and periodic

Battery can arrive later than other controls even when the control channel is already healthy.

- After the Sony control channel opens, battery now refreshes on a low-frequency background cadence instead of relying only on the initial startup sync.
- If the control channel briefly drops while macOS still owns the headset, the battery refresh path can reopen the control channel once and retry.
- Battery can still remain `Unknown` until the headset answers, but it should recover more reliably during normal use.

### Diagnostics are now easier to capture from the app

You no longer need to start with a Terminal log every time something feels off.

- The main window and the menu bar both include a `Copy Diagnostics` action.
- That report includes the app version, macOS version, connection state, live control values, paired devices, and recent session events.
- Terminal transport logs are still useful for deeper Bluetooth debugging, but the built-in report is now the first thing to attach to an issue.

### The main window was redesigned for responsiveness

The release build now prioritizes reliability and hierarchy over decorative motion.

- The continuously animated acoustic hero stage is disabled in the current build.
- Extra main-window toggle and stage transition animation was removed.
- The main window now uses a contained monolith control surface so the core actions stay visually focused and faster to scan.
- This was done because real-device testing showed the main window could feel much worse than the menu bar even when the transport layer was behaving similarly.

### Mode buttons now use full-width hit targets

The `Noise Cancelling`, `Ambient Sound`, and `Off` pills now use the entire capsule as the clickable region.

- This fix applies to the main app.
- The same hit-target fix also applies to the menu bar quick mode buttons.

## What To Expect Now

- If the XM6 is already connected in macOS, the app should show it as available instead of pretending nothing is connected.
- If the headset is paired but not connected in macOS, the app should tell you to connect it in macOS first.
- Repeated ANC and ambient switching should be more stable, and the app should recover better from a stale control session.
- Battery and some other values may still populate asynchronously after the control channel settles.

## Remaining Caveats

- Connection behavior still needs broader validation across different macOS versions and multipoint setups.
- Full manual EQ editing is still not exposed.
- Some Sony state arrives as notify traffic instead of a neat request-response exchange, so the UI can still update in stages.

For the current release-quality validation bar, use [docs/reliability-checklist.md](reliability-checklist.md).

## If You Still Hit Issues

Start by using `Copy Diagnostics` in the app or menu bar and include that report in the issue.

If transport-level Bluetooth detail is still needed, capture a Terminal log too:

```bash
cd '/path/to/xm6-macos-controller'
env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache swift run SonyMacApp 2>&1 | tee /tmp/sony-xm6-connect.log
```

The most useful lines are the ones that start with:

- `[SonyRFCOMMTransport]`
- `[SonyHeadphoneSession]`
