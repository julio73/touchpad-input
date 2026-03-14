// Sources/TouchpadInputCore/Session/TouchInputSession.swift
import AppKit
import Foundation
import Combine

// MARK: - Data Model

public struct FingerState: Identifiable, Sendable {
    public let id: String           // String(MTContact.identifier)
    public let label: String        // #1, #2, …
    public let x: CGFloat           // normalized 0…1
    public let y: CGFloat           // normalized 0…1
    public let pressure: CGFloat    // from zDensity, clamped 0…1
    public let size: CGFloat        // MTContact.size (contact area)
    public let phase: String
    public let lastEventTime: TimeInterval
    public let deltaMsFromPrev: Int?

    public init(id: String, label: String, x: CGFloat, y: CGFloat, pressure: CGFloat,
                size: CGFloat, phase: String, lastEventTime: TimeInterval, deltaMsFromPrev: Int?) {
        self.id = id; self.label = label; self.x = x; self.y = y; self.pressure = pressure
        self.size = size; self.phase = phase; self.lastEventTime = lastEventTime
        self.deltaMsFromPrev = deltaMsFromPrev
    }
}

public struct TouchLogEntry: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let fingerLabel: String
    public let phase: String
    public let x: CGFloat
    public let y: CGFloat
    public let pressure: CGFloat
    public let deltaMs: Int?
    public let rawState: Int32

    public init(timestamp: Date, fingerLabel: String, phase: String,
                x: CGFloat, y: CGFloat, pressure: CGFloat, deltaMs: Int?, rawState: Int32) {
        self.id = UUID()
        self.timestamp = timestamp; self.fingerLabel = fingerLabel; self.phase = phase
        self.x = x; self.y = y; self.pressure = pressure
        self.deltaMs = deltaMs; self.rawState = rawState
    }
}

// MARK: - TouchInputSession

@MainActor
public final class TouchInputSession: ObservableObject, @preconcurrency TouchEventReceiver {

    // MARK: Published state

    @Published public var liveFingers: [FingerState] = []
    @Published public var eventLog: [TouchLogEntry] = []
    @Published public var isActive: Bool = false
    @Published public var outputBuffer: String = ""
    @Published public var activeModifiers: Set<AnyModifierKind> = []

    // MARK: Stability settings

    @Published public var pressureFloor: Float = 0.30
    @Published public var forcePressThreshold: Float = 0.95
    @Published public var minContactSize: Float = 0.0
    @Published public var zoneCooldownMs: Double = 80.0

    // MARK: Gesture settings

    /// Minimum x-velocity (units/frame, negative = leftward) to trigger swipe-delete-word.
    public var swipeDeleteVelocityThreshold: Float = -1.5

    // MARK: Calibration

    @Published public var userCalibration: UserCalibration = .empty

    // MARK: Autocomplete

    @Published public var completions: [String] = []

    // MARK: Optional external output target (e.g. CGEventOutputTarget)

    public var externalOutputTarget: (any OutputTarget)?

    // Set by CalibrationModal to intercept touches during the calibration flow.
    public weak var activeCalibrationSession: (any CalibrationStrategy)?

    // MARK: Private dependencies

    private var zoneProvider: any InputZoneProvider
    private var resolver: any CharacterResolver
    private let modifierStrategy: any ModifierStrategy
    private let completionProvider: (any CompletionProvider)?

    private var fingerLabels: [String: String] = [:]
    private var fingerLastTime: [String: TimeInterval] = [:]
    private var lastZoneEmitTime: [String: Double] = [:]
    private var lastSwipeDeleteTime: Double = -999
    private let swipeDeleteCooldownMs: Double = 300
    private var labelCounter = 0
    private let maxLogEntries = 500

    // MARK: Init (full injection — for tests and custom integrations)

    public init(
        zoneProvider: any InputZoneProvider,
        resolver: any CharacterResolver,
        modifierStrategy: any ModifierStrategy,
        completionProvider: (any CompletionProvider)? = nil
    ) {
        self.zoneProvider = zoneProvider
        self.resolver = resolver
        self.modifierStrategy = modifierStrategy
        self.completionProvider = completionProvider
    }

    // MARK: Convenience init (what the app uses)

    public convenience init() {
        let cal = UserCalibration.load()
        self.init(
            zoneProvider: KeyGrid.default,
            resolver: CharacterEmitter(grid: .default),
            modifierStrategy: CornerModifierStrategy.default,
            completionProvider: SpellCheckerCompletionProvider()
        )
        self.userCalibration = cal
    }

    // MARK: Calibration management

    public func applyCalibration(_ calibration: UserCalibration) {
        userCalibration = calibration
        zoneProvider = KeyGrid.default
        resolver = CharacterEmitter(grid: .default)
        calibration.save()
    }

    public func resetCalibration() {
        userCalibration = .empty
        zoneProvider = KeyGrid.default
        resolver = CharacterEmitter(grid: .default)
        UserDefaults.standard.removeObject(forKey: "userCalibration")
    }

    // MARK: Autocomplete helpers

    public var currentPartialWord: String {
        if let lastSep = outputBuffer.lastIndex(where: { $0 == " " || $0 == "\n" }) {
            return String(outputBuffer[outputBuffer.index(after: lastSep)...])
        }
        return outputBuffer
    }

    public func acceptCompletion(_ word: String) {
        if let lastSep = outputBuffer.lastIndex(where: { $0 == " " || $0 == "\n" }) {
            let prefix = String(outputBuffer[...lastSep])
            outputBuffer = prefix + word + " "
        } else {
            outputBuffer = word + " "
        }
        completions = []
    }

    /// Removes the current partial word from the output buffer.
    /// If the partial word is empty (cursor is after a space), removes that trailing separator.
    public func deleteWord() {
        let partial = currentPartialWord
        if partial.isEmpty {
            if !outputBuffer.isEmpty {
                outputBuffer.removeLast()
                externalOutputTarget?.deleteLastCharacter()
            }
        } else {
            outputBuffer.removeLast(partial.count)
            for _ in partial { externalOutputTarget?.deleteLastCharacter() }
        }
        completions = completionProvider?.completions(forPartial: currentPartialWord, maxCount: 3) ?? []
    }

    // MARK: Update (main entry point from MultitouchCapture)

    public func update(mtContacts contacts: [MTContact], timestamp: Double) {
        // Detect modifiers held from the *previous* frame.
        let heldModifiers: Set<AnyModifierKind> = Set(
            liveFingers.compactMap { finger in
                modifierStrategy.modifierKind(at: Float(finger.x), y: Float(finger.y))
            }
        )

        let currentIDs = Set(contacts.map { String($0.identifier) })
        var liveLookup: [String: FingerState] = Dictionary(
            uniqueKeysWithValues: liveFingers.map { ($0.id, $0) }
        )

        // Swipe takes priority over tap: classify before acting on either.
        let isSwipeLeft = contacts.count == 2
            && activeCalibrationSession == nil
            && !heldModifiers.contains(.delete)
            && contacts.allSatisfy({ $0.normalized.velocity.x < swipeDeleteVelocityThreshold })

        // Two-finger tap: accept top autocomplete suggestion.
        let newContactIDs = currentIDs.subtracting(Set(liveLookup.keys))
        let twoFingerTapAccepted: Bool
        if newContactIDs.count >= 2 && liveLookup.isEmpty
            && !completions.isEmpty && !heldModifiers.contains(.delete) && !isSwipeLeft {
            acceptCompletion(completions[0])
            twoFingerTapAccepted = true
        } else {
            twoFingerTapAccepted = false
        }

        // Two-finger swipe-left: delete word.
        if isSwipeLeft {
            let timeSince = (timestamp - lastSwipeDeleteTime) * 1000
            if timeSince >= swipeDeleteCooldownMs {
                deleteWord()
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
                lastSwipeDeleteTime = timestamp
            }
        }

        var emittedZoneKeys: Set<String> = []

        // Synthesize "ended" for fingers that disappeared.
        for id in Set(liveLookup.keys).subtracting(currentIDs) {
            if let prev = liveLookup[id] {
                appendLog(TouchLogEntry(
                    timestamp: Date(), fingerLabel: prev.label,
                    phase: "ended", x: prev.x, y: prev.y,
                    pressure: prev.pressure, deltaMs: nil, rawState: -1
                ))
            }
            liveLookup.removeValue(forKey: id)
            fingerLastTime.removeValue(forKey: id)
        }

        // Update active contacts.
        for contact in contacts {
            let rawID = String(contact.identifier)
            let isNew = liveLookup[rawID] == nil

            if fingerLabels[rawID] == nil {
                labelCounter += 1
                fingerLabels[rawID] = "#\(labelCounter)"
            }
            let label = fingerLabels[rawID]!

            let deltaMs: Int?
            if let prev = fingerLastTime[rawID] {
                deltaMs = max(0, Int((timestamp - prev) * 1000))
            } else {
                deltaMs = nil
            }

            let x = CGFloat(contact.normalized.position.x)
            let y = CGFloat(contact.normalized.position.y)
            let pressure = CGFloat(min(max(contact.zDensity, 0), 1))

            let phase: String
            if isNew {
                phase = "began"
            } else if let prev = liveLookup[rawID],
                      abs(prev.x - x) < 0.0005 && abs(prev.y - y) < 0.0005 {
                phase = "stationary"
            } else {
                phase = "moved"
            }

            if phase == "began" && !twoFingerTapAccepted && !isSwipeLeft {
                let fx = Float(x), fy = Float(y)

                if let calSession = activeCalibrationSession {
                    calSession.recordTap(x: fx, y: fy)
                } else {
                    // Adjust tap by global calibration offset before zone lookup.
                    let calOff = userCalibration.globalOffset
                    let calX = fx - calOff.dx
                    let calY = fy - calOff.dy

                    // Suppress "began" only for modifier zones that are NOT already held.
                    let modifier = modifierStrategy.modifierKind(at: calX, y: calY)
                    let isInUnheldModifierZone: Bool
                    if let mod = modifier {
                        isInUnheldModifierZone = !heldModifiers.contains(mod)
                    } else {
                        isInUnheldModifierZone = false
                    }

                    if !isInUnheldModifierZone {
                        if heldModifiers.contains(.delete) {
                            // Delete-hold: remove last char
                            if !outputBuffer.isEmpty {
                                outputBuffer.removeLast()
                                externalOutputTarget?.deleteLastCharacter()
                            }
                            completions = completionProvider?.completions(
                                forPartial: currentPartialWord, maxCount: 3
                            ) ?? []
                        } else if let zoneID = zoneProvider.zoneID(at: calX, y: calY) {
                            if !emittedZoneKeys.contains(zoneID) {
                                emittedZoneKeys.insert(zoneID)
                                let passesSize = contact.size >= minContactSize
                                let timeSinceMs = (timestamp - (lastZoneEmitTime[zoneID] ?? -999)) * 1000
                                let passesCooldown = timeSinceMs >= zoneCooldownMs
                                if passesSize && passesCooldown {
                                    var effectivePressure = Float(pressure)
                                    if heldModifiers.contains(.shift),
                                       effectivePressure >= pressureFloor, effectivePressure < 0.70 {
                                        effectivePressure = 0.70
                                    }
                                    if let ch = resolver.character(
                                        forZoneID: zoneID,
                                        pressure: effectivePressure,
                                        modifiers: heldModifiers,
                                        pressureFloor: pressureFloor,
                                        forcePressThreshold: forcePressThreshold
                                    ) {
                                        outputBuffer.append(ch)
                                        externalOutputTarget?.emit(character: ch)
                                        lastZoneEmitTime[zoneID] = timestamp

                                        // Haptic feedback
                                        NSHapticFeedbackManager.defaultPerformer
                                            .perform(.generic, performanceTime: .default)

                                        // Incremental calibration refinement
                                        if let zone = KeyGrid.default.zones.first(where: { String($0.character) == zoneID }) {
                                            userCalibration.refine(
                                                character: zone.character,
                                                tapX: fx, tapY: fy,
                                                in: KeyGrid.default
                                            )
                                            userCalibration.save()
                                        }

                                        completions = completionProvider?.completions(
                                            forPartial: currentPartialWord, maxCount: 3
                                        ) ?? []
                                    }
                                }
                            }
                        }
                    }
                }
            }

            if phase != "stationary" {
                appendLog(TouchLogEntry(
                    timestamp: Date(), fingerLabel: label,
                    phase: phase, x: x, y: y,
                    pressure: pressure, deltaMs: deltaMs,
                    rawState: contact.state
                ))
            }

            fingerLastTime[rawID] = timestamp
            liveLookup[rawID] = FingerState(
                id: rawID, label: label,
                x: x, y: y, pressure: pressure,
                size: CGFloat(contact.size),
                phase: phase, lastEventTime: timestamp,
                deltaMsFromPrev: deltaMs
            )
        }

        liveFingers = Array(liveLookup.values).sorted { $0.label < $1.label }
        activeModifiers = heldModifiers
    }

    // MARK: Clear

    public func clearAll() {
        eventLog = []
        liveFingers = []
        outputBuffer = ""
        activeModifiers = []
        completions = []
        fingerLabels = [:]
        fingerLastTime = [:]
        lastZoneEmitTime = [:]
        lastSwipeDeleteTime = -999
        labelCounter = 0
        activeCalibrationSession = nil
        externalOutputTarget?.clear()
    }

    // MARK: Private

    private func appendLog(_ entry: TouchLogEntry) {
        eventLog.append(entry)
        if eventLog.count > maxLogEntries {
            eventLog.removeFirst(eventLog.count - maxLogEntries)
        }
    }
}
