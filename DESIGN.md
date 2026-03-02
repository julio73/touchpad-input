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
