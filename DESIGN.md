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

---

## Character Emitter

### `CharacterEmitter` Type

```swift
/// Translates "began" touch events into characters using a KeyGrid,
/// applying pressure-based modifier logic.
final class CharacterEmitter {
    private let grid: KeyGrid

    /// Accumulated output — exposed as @Published on TouchDiagnosticSession in M2.
    var outputBuffer: String = ""

    init(grid: KeyGrid = .default) { self.grid = grid }

    /// Called for each contact whose phase is "began".
    /// Returns the character to emit (possibly modified by pressure), or nil for a miss.
    func characterForTouch(at x: Float, y: Float, pressure: Float) -> Character?
}
```

### Emission Rules

1. **Trigger phase**: emission fires **only on `"began"`** — the first frame a finger
   appears. Subsequent `"moved"` or `"stationary"` events for the same finger do not
   emit.
2. **Zone lookup**: `grid.zone(at: x, y:)` is called with the contact's normalized
   position. A `nil` result (miss zone) produces no output.
3. **Pressure gate**: touches below `zDensity` 0.30 are ignored entirely (see Pressure
   Thresholds below). This prevents phantom emissions from incidental brushing.
4. **Pressure modifier**: the emitted character may be uppercased or altered based on
   `zDensity` (see table below).
5. **Output**: the character is appended to `CharacterEmitter.outputBuffer`.

### Integration Point

`TouchDiagnosticSession.update()` will be extended in M2 to call the emitter after
phase detection:

```swift
// Inside update(), after phase is determined for a contact:
if phase == "began" {
    if let ch = emitter.characterForTouch(
        at: Float(x), y: Float(y), pressure: Float(contact.zDensity)
    ) {
        outputBuffer.append(ch)   // outputBuffer is @Published on TouchDiagnosticSession
    }
}
```

`TouchDiagnosticSession` gains:
- A `CharacterEmitter` instance property.
- `@Published var outputBuffer: String = ""` — displayed in a new output text area in
  `ContentView`.
- `outputBuffer` is reset by `clearAll()`.

---

## Multi-Touch Disambiguation

When two or more fingers touch down in the **same frame**, `update()` processes
contacts in the order delivered by the hardware callback. To produce deterministic
output when multiple fingers land in the same zone simultaneously:

**Rule:** When multiple "began" contacts fall in the **same zone** within a single
frame, only the contact with the **lowest `identifier` value** emits. All others are
silently skipped for that frame.

**Implementation sketch:**

```swift
var emittedZoneKeys: Set<String> = []   // "xMin-yMin" uniquely identifies a zone

for contact in contacts {
    guard phase(for: contact, in: liveLookup) == "began" else { continue }
    guard let zone = grid.zone(at: Float(contact.normalized.position.x),
                               y: Float(contact.normalized.position.y)) else { continue }
    let key = "\(zone.xMin)-\(zone.yMin)"
    guard !emittedZoneKeys.contains(key) else { continue }   // lower id arrived first
    emittedZoneKeys.insert(key)
    // emit character for this zone
}
```

**Rationale:** The hardware assigns monotonically increasing identifiers within a
session; contacts that arrive in the same callback frame are processed in array order
(lower index = lower identifier in practice). Using the first-seen contact approximates
"the intentional finger" when two fingers accidentally land on the same zone.

---

## Pressure Thresholds (`zDensity`)

`zDensity` is clamped to 0…1 by `TouchDiagnosticSession`. Observed ranges on a
standard MacBook trackpad during M1 diagnostics:

- Feather/incidental contact: ~0.05–0.20
- Normal tap: ~0.25–0.50
- Deliberate press: ~0.55–0.80
- Force-touch threshold: ~0.85+

| `zDensity` range | Behavior |
|------------------|----------|
| 0.00 – 0.29      | **No emission** — below confidence threshold; touch ignored |
| 0.30 – 0.69      | **Normal tap** — emit lowercase character from zone |
| 0.70 – 0.84      | **Firm tap** — emit uppercase character (implicit Shift) |
| 0.85 – 1.00      | **Force press** — emit alternate character (behavior TBD in M3) |

> These thresholds are initial estimates. The `zDensity` histogram collected during
> M1 testing should be used to calibrate final values. A per-user calibration UI is
> a candidate feature for M4.

### Shift and Modifier State (M3 Preview)

Pressure-based Shift is stateless: each tap independently determines case from its
own `zDensity`. There is no "hold Shift" state in M2. A dedicated modifier-hold
mechanism (e.g., a thumb-corner zone held while other fingers tap) is deferred to M3.
