# Changelog

## 1.0.0 - 2026-04-21

Sony Audio 1.0.0 is the first release that feels like a polished Mac app instead of a protocol preview.

### Highlights

- Rebuilt the main window around a contained monolith control surface with clearer hierarchy and faster interaction.
- Moved to a macOS-first headset connection model so the app follows the system audio state instead of inventing its own.
- Added automatic Sony control-channel reopen and retry behavior when commands time out but macOS still owns the headset.
- Reduced main-window choppiness by removing heavier decorative rendering and keeping Bluetooth work off the UI thread.
- Added built-in `Copy Diagnostics` support in both the main window and the menu bar to make GitHub issue reports actionable.
- Improved periodic battery refresh and more accurate connection/status messaging.
- Kept resident menu bar controls aligned with the same lower-friction control flow as the main app.
- Kept release packaging ready for `.app`, `.zip`, `.dmg`, and Homebrew distribution.

### Upgrade Notes

- This release still expects the headset to be connected in macOS first.
- Homebrew installs continue to track the GitHub Releases DMG for this repository.
- Existing manual installs in `/Applications` may need to be moved aside before a Homebrew install or upgrade.

### Known Limitations

- Full manual EQ editing is still not exposed.
- Virtual surround and sound-position controls are still not mapped.
- Some state refreshes still arrive asynchronously from Sony notify traffic.
- Multipoint edge cases can still vary depending on nearby devices and the current macOS Bluetooth state.

### Previous Preview Tags

- `0.3.1`
- `0.3.0`
- `0.2.0`
- `0.1.0`
