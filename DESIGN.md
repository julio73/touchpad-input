# M2 Character Emission — Architecture Design

## Project Context

Touchpad Input converts MacBook trackpad touches into text, allowing silent typing
on a surface that provides no physical click feedback.

### Milestone Status

| Milestone | Description | Status |
|-----------|-------------|--------|
| M1 | Input Capture — raw touch events visible, diagnostics working | ✅ Complete |
| M2 | Character Emission — touch-to-key mapping, output buffer | ⬜ Next |
| M3 | Multi-touch + Pressure — concurrent touches, pressure-action path | ⬜ Pending |
| M4 | Stability Pass — reduce accidental hits, improve mapping consistency | ⬜ Pending |

### Purpose of This Document

This document specifies the architecture for M2: how the trackpad surface is divided
into a key grid, how touch events are translated into character emissions, and how
multi-touch and pressure are handled. It defines the `KeyGrid` and `CharacterEmitter`
types that will be introduced in M2 and their integration with the existing
`TouchDiagnosticSession`.

### Existing Components (M1)

The following types are already implemented and remain unchanged in M2:

- **`MTContact`** — raw hardware contact struct mirrored from `MultitouchSupport.framework`.
  Provides normalized x/y position (0…1), `zDensity` (pressure-like), and `identifier`
  (stable across a touch session).
- **`MultitouchCapture`** — singleton that manages `MultitouchSupport` device registration
  and routes callbacks to the session.
- **`TouchDiagnosticSession`** — processes `MTContact` arrays into `FingerState` values
  and a `TouchLogEntry` event log. Detects phases: `began`, `moved`, `stationary`, `ended`.
- **`ContentView`** / subviews — SwiftUI visualization of live touches and event log.

---

## Trackpad Coordinate Space

MultitouchSupport provides normalized coordinates in the range 0…1 for both axes:

- **X axis**: 0 = left edge, 1 = right edge
- **Y axis**: 0 = bottom edge (near the user), 1 = top edge (away from the user)

> Note: SwiftUI's coordinate system has Y=0 at the top. `TrackpadSurface` already
> compensates with `(1.0 - finger.y)`. Key grid zones use the native trackpad convention
> (Y=0 at bottom) throughout.

### Row Boundaries

The trackpad is divided into **3 key rows** plus a spacebar zone at the bottom:

```
y = 1.0 ──────────────────────────────────────────────────
         TOP ROW     (Q W E R T Y U I O P)   y ∈ [0.65, 1.0)
y = 0.65 ─────────────────────────────────────────────────
         HOME ROW    (A S D F G H J K L ;)   y ∈ [0.30, 0.65)
y = 0.30 ─────────────────────────────────────────────────
         BOTTOM ROW  (Z X C V B N M , . /)   y ∈ [0.08, 0.30)
y = 0.08 ─────────────────────────────────────────────────
         SPACE BAR                           y ∈ [0.00, 0.08)
y = 0.00 ──────────────────────────────────────────────────
```

### Column Boundaries

Each row has **10 evenly spaced columns** spanning x ∈ [0.02, 0.98] (2% margins on
each side). Column width = (0.98 − 0.02) / 10 = **0.096** per column.

| Column | x range          | Top row | Home row | Bottom row |
|--------|------------------|---------|----------|------------|
| 0      | [0.020, 0.116)   | Q       | A        | Z          |
| 1      | [0.116, 0.212)   | W       | S        | X          |
| 2      | [0.212, 0.308)   | E       | D        | C          |
| 3      | [0.308, 0.404)   | R       | F        | V          |
| 4      | [0.404, 0.500)   | T       | G        | B          |
| 5      | [0.500, 0.596)   | Y       | H        | N          |
| 6      | [0.596, 0.692)   | U       | J        | M          |
| 7      | [0.692, 0.788)   | I       | K        | ,          |
| 8      | [0.788, 0.884)   | O       | L        | .          |
| 9      | [0.884, 0.980)   | P       | ;        | /          |

**Space zone:** Full width (x ∈ [0.02, 0.98], y ∈ [0.00, 0.08)), emits `" "`.

**Miss zones:** Touches outside all defined zones (extreme corners, margins) produce
no emission.

### `KeyGrid` Type

```swift
/// A single key zone on the trackpad surface.
struct KeyZone {
    let character: Character   // character emitted on a normal tap
    let xMin, xMax: Float      // normalized x bounds [xMin, xMax)
    let yMin, yMax: Float      // normalized y bounds [yMin, yMax)
}

/// Immutable grid of all key zones; constructed once at startup.
struct KeyGrid {
    let zones: [KeyZone]       // 31 zones: 10 top + 10 home + 10 bottom + 1 space

    /// Returns the zone whose bounds contain (x, y), or nil if outside all zones.
    /// O(n) linear scan over 31 zones — sufficient for real-time use.
    func zone(at x: Float, y: Float) -> KeyZone?

    /// Default QWERTY grid using the coordinate boundaries defined above.
    static let `default`: KeyGrid
}
```
