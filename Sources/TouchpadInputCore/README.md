# TouchpadInputCore

Swift SDK for building trackpad-based silent typing experiences on macOS.
The flagship app (TouchpadInput) is built on top of this library.

## Requirements

- macOS 12+
- Swift 5.9+ / Xcode 15+
- Accessibility permission (for `CGEventOutputTarget` system injection)

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/julio73/touchpad-input", from: "1.0.0")
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "TouchpadInputCore", package: "touchpad-input")
    ])
]
```

## Quick Start

```swift
import TouchpadInputCore

// 1. Create a session with system-wide key injection
let session = TouchInputSession()
session.externalOutputTarget = CGEventOutputTarget()

// 2. Request Accessibility permission (shows system prompt once)
CGEventOutputTarget.requestAccessibilityPermission()

// 3. Wire double-Control-tap to toggle capture on/off
MultitouchCapture.shared.setupDoubleControlToggle(for: session)
```

That's it. The session listens for raw trackpad contacts, maps them to the built-in QWERTY `KeyGrid`, resolves characters via `CharacterEmitter`, and injects keystrokes into the frontmost app.

## Architecture

`TouchInputSession` is the single entry point. It composes six protocol slots:

| Protocol | Default | Purpose |
|---|---|---|
| `InputZoneProvider` | `KeyGrid` | Maps (x, y) → zone ID (e.g. `"q"`) |
| `CharacterResolver` | `CharacterEmitter` | Zone ID + pressure → `Character` |
| `ModifierStrategy` | `CornerModifierStrategy` | Corner zones → shift / delete hold |
| `OutputTarget` | `BufferOutputTarget` | Receives emitted characters |
| `CompletionProvider` | `SpellCheckerCompletionProvider` | Word suggestions for partial input |
| `CalibrationStrategy` | _(none)_ | Records taps to refine zone layout |

Replace any slot with your own conformance to customise behaviour.

## Gestures

| Gesture | Action |
|---|---|
| Single finger touch | Emit character for that zone |
| Hold corner (bottom-left) | Shift modifier — next character uppercase |
| Hold corner (bottom-right) | Delete modifier — hold to delete |
| Two-finger swipe left | Delete current partial word |
| Two-finger tap | Accept top autocomplete suggestion |
| Double-tap Control key | Toggle capture on / off |

## Customising the Layout

`KeyGrid` is an `InputZoneProvider` built from an array of `KeyZone` values.
You can supply your own grid or adjust the default:

```swift
// Adjust calibration offsets
let cal = UserCalibration.load()          // persisted via UserDefaults
let grid = KeyGrid.default.applying(calibration: cal)

// Build a fully custom grid
let myGrid = KeyGrid(zones: myZones)
let session = TouchInputSession(
    zoneProvider: myGrid,
    resolver: CharacterEmitter(),
    modifierStrategy: CornerModifierStrategy()
)
```

## Custom Output Target

Route emitted characters anywhere by implementing `OutputTarget`:

```swift
@MainActor
final class LogOutputTarget: OutputTarget {
    func emit(character: Character) { print("emitted: \(character)") }
    func deleteLastCharacter()      { print("delete") }
    func clear()                    { print("clear") }
}

session.externalOutputTarget = LogOutputTarget()
```

Fan-out to multiple targets with `MultiOutputTarget`:

```swift
session.externalOutputTarget = MultiOutputTarget([
    CGEventOutputTarget(),
    LogOutputTarget()
])
```

## Custom Completion Provider

```swift
struct MyDictionary: CompletionProvider {
    func completions(forPartial partial: String, maxCount: Int) -> [String] {
        // query your own word list
    }
}

let session = TouchInputSession(
    zoneProvider: KeyGrid.default,
    resolver: CharacterEmitter(),
    modifierStrategy: CornerModifierStrategy(),
    completionProvider: MyDictionary()
)
```

## Custom Modifier Strategy

```swift
struct MyModifiers: ModifierStrategy {
    func modifierKind(at x: Float, y: Float) -> AnyModifierKind? {
        y < 0.1 ? .shift : nil   // top strip = shift
    }
    var zoneLabels: [AnyModifierKind: String] { [.shift: "⇧"] }
}
```

`AnyModifierKind` is extensible — define your own modifier kinds beyond `.shift` and `.delete`:

```swift
extension AnyModifierKind {
    static let fn = AnyModifierKind(rawValue: "fn")
}
```

## Observing Session State

`TouchInputSession` is an `ObservableObject`. Use it directly in SwiftUI:

```swift
@StateObject var session = TouchInputSession()

var body: some View {
    VStack {
        Text(session.outputBuffer)
        Text(session.completions.first ?? "")
            .foregroundStyle(.secondary)
    }
}
```

Published properties:

| Property | Type | Description |
|---|---|---|
| `outputBuffer` | `String` | Accumulated typed text |
| `completions` | `[String]` | Current autocomplete suggestions |
| `liveFingers` | `[FingerState]` | Active touch contacts |
| `isActive` | `Bool` | Whether capture is running |
| `activeModifiers` | `Set<AnyModifierKind>` | Held modifier zones |
| `userCalibration` | `UserCalibration` | Current calibration offsets |

## Tunable Parameters

```swift
session.pressureFloor          // Float, default 0.30 — minimum zDensity to register a tap
session.minContactSize         // Float, default 0.0  — minimum contact area filter
session.zoneCooldownMs         // Double, default 80  — ms before same zone can re-emit
session.swipeDeleteVelocityThreshold  // Float, default -1.5 — x-velocity for swipe-delete
```

## System Injection Notes

`CGEventOutputTarget` uses `CGEvent` keyboard events to inject keystrokes into the frontmost app.

- Requires Accessibility permission (`AXIsProcessTrusted()`)
- v1 supports US QWERTY keycodes only (a–z, A–Z, 0–9, common symbols)
- Call `CGEventOutputTarget.requestAccessibilityPermission()` at launch to trigger the system prompt

## License

TouchpadInputCore is released under the MIT License.
