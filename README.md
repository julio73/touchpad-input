# Touchpad Input

Silent macOS keyboard on the trackpad — open-core Swift SDK + flagship app.

Type without pressing keys. Place fingers on the MacBook trackpad, and multi-touch contacts are mapped to a QWERTY grid and injected system-wide as real keystrokes.

## What works

- **QWERTY key grid** — trackpad surface divided into letter/number zones
- **Force-press alt chars** — press harder on a key to emit its alternate character (e.g. `e` → `é`)
- **Shift zone** — hold bottom-left corner to capitalize the next character
- **Delete zone** — hold bottom-right corner to continuously delete
- **Two-finger swipe left** — delete current partial word instantly
- **Two-finger tap** — accept top autocomplete suggestion
- **Autocomplete** — live word suggestions powered by macOS spell checker
- **Calibration** — tap-to-calibrate modal refines zone positions to your hand
- **Haptic feedback** — confirmation tap on each emitted character
- **System injection** — `CGEventOutputTarget` injects keystrokes into any app via Accessibility API
- **Double-tap Control** — toggle capture on/off without leaving the keyboard

## Requirements

- macOS 12+
- Xcode or Xcode Command-Line Tools
- Accessibility permission (for the global key monitor and CGEvent injection)

## Run

```bash
swift build
swift run
```

On first launch macOS will prompt for Accessibility access. Grant it in **System Settings → Privacy & Security → Accessibility**.

Once running, double-tap either Control key to start/stop touch capture.

## SDK

The core logic lives in `TouchpadInputCore`, a standalone MIT-licensed Swift package. Build your own trackpad-input app or plugin on top of it.

See [`Sources/TouchpadInputCore/README.md`](Sources/TouchpadInputCore/README.md) for the quick-start guide, protocol reference, and customisation examples.

## License

The flagship app (`TouchpadInputApp`) is source-available. The SDK (`TouchpadInputCore`) is MIT licensed.
