# Touchpad Input (MVP)

New macOS input interface where a keyboard is emulated on the trackpad for silent typing.

## MVP Goal

Build a desktop app that converts multi-touch trackpad interactions into text with low noise and fast feedback.

For MVP we will type **inside the app first** (not system-wide input injection yet).

## User Story (MVP)

As a user, I can place multiple fingers on the MacBook trackpad and produce letters/commands without pressing physical keys, so I can type quietly.

## MVP Scope

1. **Trackpad touch capture**
   - Detect individual touches and positions.
   - Support concurrent touches (multi-finger).
2. **Touch-to-key mapping**
   - Map touch coordinates to a key grid.
   - Emit a character when a touch begins in a region.
3. **Text output buffer**
   - Show produced characters in an in-app text area.
4. **Force Touch hook (experimental)**
   - Detect pressure changes where available.
   - Map pressure thresholds to alternate behavior (ex: Shift/delete).
5. **Debug visualization**
   - Show current touch points and mapped keys for tuning.

## Explicitly Out of Scope (for now)

- System-wide keyboard emulation.
- Full keyboard layout parity.
- Predictive text/autocorrect.
- Accessibility/permission polish.
- Production packaging/distribution.

## Technical Plan

1. Create a macOS app shell with AppKit touch-capturing view.
2. Implement a simple key grid model (letters + space + delete).
3. Add a session state object to collect emitted characters.
4. Add pressure event handling and simple action mapping.
5. Add metrics logging (touch count, key hit rate) for tuning.

## Milestones

1. **M1: Input Capture**
   - Touch events visible on screen.
2. **M2: Character Emission**
   - Touch regions emit characters into output.
3. **M3: Multi-touch + Pressure**
   - Multiple simultaneous touches handled correctly.
   - Pressure action path tested on supported hardware.
4. **M4: Stability Pass**
   - Reduce accidental hits and improve mapping consistency.

## Current Status

- [x] M1: Touch capture working (MultitouchSupport bridge, live finger dots, event log)
- [x] M2: Character emission (QWERTY key grid, output buffer, force-press alt chars, key grid overlay)
- [x] M3: Multi-touch + pressure handling (modifier-hold zones: shift + delete corners)
- [x] M4: Stability pass (contact-size filter, zone cooldown, adjustable pressure floor, settings panel)

## Run

Requirements: macOS 11+, Xcode command-line tools or full Xcode.

```bash
swift build
swift run
```

**Accessibility permission required:** On first launch, macOS will prompt for
Accessibility access (needed for the global key monitor that toggles capture).
Grant it in System Settings → Privacy & Security → Accessibility.

Once running, double-tap either Control key to start/stop touch capture.
