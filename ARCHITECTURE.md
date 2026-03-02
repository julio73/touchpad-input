# Architecture

Touchpad Input is a single-process macOS app written in Swift (AppKit + SwiftUI). It captures raw multi-touch data from the trackpad using a private system framework, processes those contacts into structured finger state, and displays the results in a diagnostic UI. This document describes how each layer works and how they connect.

## MultitouchSupport Framework Bridge

### Why dlopen

`MultitouchSupport.framework` is a private Apple framework with no public headers and no SDK linkage. The app loads it at runtime using `dlopen` and resolves individual function symbols with `dlsym`. This avoids a hard link-time dependency that would cause the binary to refuse to launch if the framework path ever changes, and it means the code can explain what it is doing rather than relying on invisible implicit imports.

```swift
private let lib = dlopen(
    "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
    RTLD_LAZY
)
```

Three symbols are resolved when capture starts: `MTDeviceCreateList`, `MTRegisterContactFrameCallback`, and `MTDeviceStart`. A fourth, `MTDeviceStop`, is resolved when capture stops.

### MTContact Struct Layout

The framework delivers touch data as a packed C struct array. The Swift `MTContact` struct mirrors that layout exactly. Field order and padding must match the C ABI or finger positions will appear scrambled.

| Field            | Offset | Type             | Description                                      |
|------------------|--------|------------------|--------------------------------------------------|
| `frame`          | 0      | `Int32`          | Frame counter from the hardware                  |
| *(padding)*      | 4      | —                | 4 bytes to align `timestamp` to 8-byte boundary  |
| `timestamp`      | 8      | `Double`         | Hardware timestamp (seconds)                     |
| `identifier`     | 16     | `Int32`          | Stable ID for this touch session (finger tracking)|
| `state`          | 20     | `Int32`          | Raw hardware state value                         |
| `fingerId`       | 24     | `Int32`          | Per-device finger slot index                     |
| `handId`         | 28     | `Int32`          | Hand grouping index                              |
| `normalized`     | 32     | `MTPoint`        | Position + velocity, each component in 0...1     |
| `size`           | 48     | `Float`          | Contact area (normalized)                        |
| `unknown1`       | 52     | `Int32`          | Reserved / undocumented                          |
| `angle`          | 56     | `Float`          | Contact ellipse rotation angle                   |
| `majorAxis`      | 60     | `Float`          | Major axis length of the contact ellipse         |
| `minorAxis`      | 64     | `Float`          | Minor axis length of the contact ellipse         |
| `absoluteVector` | 68     | `MTPoint`        | Absolute position + velocity in device units     |
| `unknown2`       | 84     | `(Int32, Int32)` | Reserved / undocumented (two Int32 fields)       |
| `zDensity`       | 92     | `Float`          | Pressure-like value; used as a proxy for force   |

`MTPoint` is a 16-byte struct: `position: MTVector` (8 bytes) followed by `velocity: MTVector` (8 bytes). `MTVector` holds two `Float` fields (`x`, `y`).

### C Callback Pattern

`MTRegisterContactFrameCallback` expects a plain C function pointer. Swift closures that capture variables from their enclosing scope cannot be converted to C function pointers. The callback is therefore a module-level `let` constant declared with `@convention(c)`:

```swift
private let mtFrameCallback: MTCallbackFn = { _, rawPtr, count, timestamp, _ in
    guard let rawPtr, count > 0 else { return }
    let n = Int(count)
    let contacts = rawPtr.withMemoryRebound(to: MTContact.self, capacity: n) { ptr in
        Array(UnsafeBufferPointer(start: ptr, count: n))
    }
    DispatchQueue.main.async {
        MultitouchCapture.shared.session?.update(mtContacts: contacts, timestamp: timestamp)
    }
}
```

Because the callback cannot hold a reference to any Swift object directly, it routes through the `MultitouchCapture.shared` singleton and dispatches to the main queue before touching any `@Published` state.

---

## MultitouchCapture Singleton

`MultitouchCapture` is a `final class` with a `static let shared` instance. It is marked `@unchecked Sendable` because its mutable state (`devices`, `keyMonitor`, `lastControlPressTime`, `session`) is accessed only from the main thread or within the C callback's `DispatchQueue.main.async` dispatch, but the compiler cannot verify this automatically due to the `@convention(c)` callback boundary.

### Responsibilities

- **Device enumeration** — calls `MTDeviceCreateList()` to obtain the list of available multitouch devices on `start()`.
- **Callback registration** — calls `MTRegisterContactFrameCallback(device, mtFrameCallback)` for each device.
- **Device lifecycle** — calls `MTDeviceStart(device, 0)` to begin streaming and `MTDeviceStop(device)` to halt it.
- **Session reference** — holds a `weak var session: TouchDiagnosticSession?` so the callback can deliver data without creating a retain cycle.

### Toggle Lifecycle

`setupDoubleControlToggle(for:)` is called from `ContentView.onAppear`. It installs a global event monitor via `NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged)` that listens for Control key presses system-wide and toggles capture on a double-tap. `teardownDoubleControlToggle()` is called from `ContentView.onDisappear`; it removes the monitor, resets the timing state, and stops all devices.

---

## TouchDiagnosticSession

`TouchDiagnosticSession` is an `ObservableObject` that converts raw `[MTContact]` arrays into SwiftUI-ready published state.

### Published State

| Property      | Type              | Description                                   |
|---------------|-------------------|-----------------------------------------------|
| `liveFingers` | `[FingerState]`   | Currently active touches, sorted by label     |
| `eventLog`    | `[TouchLogEntry]` | Timestamped history of touch events (max 500) |
| `isActive`    | `Bool`            | Whether the capture pipeline is running       |

### Data Flow

Each call to `update(mtContacts:timestamp:)` (always on the main queue) does the following:

1. **Synthesize "ended" events** — compares the incoming contact IDs against the current `liveFingers` dictionary. Any finger present in `liveFingers` but absent from the new frame is considered lifted; an `ended` log entry is appended and the finger is removed.

2. **Phase detection** — for each incoming contact:
   - If the contact ID has no entry in `liveFingers` → phase is `began`.
   - If the contact ID exists and position has not moved more than 0.0005 in either axis → phase is `stationary`.
   - Otherwise → phase is `moved`.

3. **Finger labeling** — the first time a given `identifier` is seen, it is assigned the next sequential label (`#1`, `#2`, ...) via `labelCounter`. Labels are stored in `fingerLabels: [String: String]` and persist for the lifetime of the session (they are not reused after a finger lifts).

4. **Log capping** — after appending a new `TouchLogEntry`, if `eventLog.count` exceeds 500 the oldest entries are trimmed: `eventLog.removeFirst(eventLog.count - maxLogEntries)`.

5. **State publication** — `liveFingers` is replaced with the updated dictionary values, sorted lexicographically by label so the table renders in a stable order.
