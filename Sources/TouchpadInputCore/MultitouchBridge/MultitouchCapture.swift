// Sources/TouchpadInputCore/MultitouchBridge/MultitouchCapture.swift
import AppKit
import Darwin

// MARK: - TouchEventReceiver

/// Protocol implemented by any session that can receive raw multitouch data.
public protocol TouchEventReceiver: AnyObject {
    func update(mtContacts: [MTContact], timestamp: Double)
    var isActive: Bool { get set }
    var liveFingers: [FingerState] { get set }
}

// MARK: - C callback

// Cannot capture Swift context; routes through the singleton.
private typealias MTCallbackFn = @convention(c) (
    UnsafeRawPointer?,   // device (unused)
    UnsafeRawPointer?,   // contacts array (rebound to MTContact inside)
    Int32,               // count
    Double,              // timestamp
    Int32                // frame number (unused)
) -> Void

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

// MARK: - MultitouchCapture

public final class MultitouchCapture: @unchecked Sendable {
    public static let shared = MultitouchCapture()

    nonisolated(unsafe) public weak var session: (any TouchEventReceiver)?
    private nonisolated(unsafe) var keyMonitor: Any?
    private nonisolated(unsafe) var lastControlPressTime: TimeInterval = 0
    private nonisolated(unsafe) var devices: [AnyObject] = []

    private let lib = dlopen(
        "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
        RTLD_LAZY
    )

    /// Call from onAppear — double-tap either Control key toggles capture.
    public func setupDoubleControlToggle(for session: any TouchEventReceiver) {
        self.session = session
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return }
            guard (event.keyCode == 59 || event.keyCode == 62),
                  event.modifierFlags.contains(.control) else { return }
            let now = event.timestamp
            if now - self.lastControlPressTime < 0.35 {
                self.lastControlPressTime = 0
                DispatchQueue.main.async {
                    guard let s = self.session else { return }
                    if s.isActive { self.stop() } else { self.start(session: s) }
                }
            } else {
                self.lastControlPressTime = now
            }
        }
    }

    /// Call from onDisappear.
    public func teardownDoubleControlToggle() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        lastControlPressTime = 0
        stop()
    }

    public func start(session: any TouchEventReceiver) {
        stopDevices()
        self.session = session

        guard let lib else {
            print("[MT] could not open MultitouchSupport.framework")
            return
        }

        typealias CreateListFn = @convention(c) () -> CFArray
        typealias RegisterFn   = @convention(c) (UnsafeRawPointer, MTCallbackFn) -> Void
        typealias StartFn      = @convention(c) (UnsafeRawPointer, Int32) -> Void

        guard
            let cs = dlsym(lib, "MTDeviceCreateList"),
            let rs = dlsym(lib, "MTRegisterContactFrameCallback"),
            let ss = dlsym(lib, "MTDeviceStart")
        else {
            print("[MT] could not resolve symbols")
            return
        }

        let createList  = unsafeBitCast(cs, to: CreateListFn.self)
        let registerCb  = unsafeBitCast(rs, to: RegisterFn.self)
        let startDevice = unsafeBitCast(ss, to: StartFn.self)

        devices = createList() as [AnyObject]
        for device in devices {
            let raw = Unmanaged.passUnretained(device).toOpaque()
            registerCb(raw, mtFrameCallback)
            startDevice(raw, 0)
        }
        session.isActive = true
    }

    public func stop() {
        session?.isActive = false
        session?.liveFingers = []
        stopDevices()
    }

    private func stopDevices() {
        defer { devices = [] }
        guard let lib, !devices.isEmpty else { return }
        typealias StopFn = @convention(c) (UnsafeRawPointer) -> Void
        guard let sym = dlsym(lib, "MTDeviceStop") else { return }
        let stopDevice = unsafeBitCast(sym, to: StopFn.self)
        for device in devices {
            stopDevice(Unmanaged.passUnretained(device).toOpaque())
        }
    }
}
