#!/usr/bin/swift

import Cocoa
import Foundation

// MARK: - Unified Mac Utilities daemon
//
// Single process, single permission (Accessibility). Hosts multiple features:
//   1. Desktop Switcher : Ctrl + scroll -> switch desktop
//   2. ScrollFix        : invert mouse scroll (trackpad stays natural)
//
// To add a new feature, just add its behavior below; no separate binary and
// no additional permission are needed.

final class MacUtilities: NSObject {

    // MARK: Desktop switcher state
    private var ctrlPressed = false
    private var lastScrollTime: TimeInterval = 0
    private let scrollCooldown: TimeInterval = 0.2

    // MARK: Tap
    private var eventTap: CFMachPort?
    private var retryTimer: Timer?

    // MARK: - Startup
    func start() {
        // Ask for the permission once (passes immediately if already granted).
        // Do NOT terminate when it is missing — this avoids the old
        // "terminate + KeepAlive" infinite permission-prompt loop.
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)

        setupTapIfPossible()

        // If permission is not granted yet: retry periodically WITHOUT re-prompting.
        if eventTap == nil {
            retryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                guard AXIsProcessTrusted() else { return }   // wait silently
                self.setupTapIfPossible()
                if self.eventTap != nil {
                    self.retryTimer?.invalidate()
                    self.retryTimer = nil
                    fputs("Accessibility granted — utilities active.\n", stderr)
                }
            }
        }

        setupSignalHandler()
    }

    // MARK: - Event tap setup
    private func setupTapIfPossible() {
        guard eventTap == nil else { return }
        guard AXIsProcessTrusted() else { return }

        let eventMask = (1 << CGEventType.scrollWheel.rawValue)
                      | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let mySelf = Unmanaged<MacUtilities>.fromOpaque(refcon).takeUnretainedValue()
                return mySelf.handleEvent(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            fputs("Failed to create event tap (permission not ready yet).\n", stderr)
            return
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    // MARK: - Event dispatch
    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .flagsChanged:
            ctrlPressed = event.flags.contains(.maskControl)

        case .scrollWheel:
            // Priority: if Ctrl is held, switch desktop and consume the event.
            if ctrlPressed {
                handleDesktopSwitch(event)
                return nil
            }
            // Otherwise: ScrollFix (invert if it's a mouse).
            applyScrollFix(event)

        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // Re-enable the tap if the system disables it.
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }

        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }

    // MARK: - Feature 1: Desktop Switcher
    private enum Direction { case left, right }

    private func handleDesktopSwitch(_ event: CGEvent) {
        let scrollDelta = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let now = CACurrentMediaTime()
        guard now - lastScrollTime > scrollCooldown else { return }
        guard scrollDelta != 0 else { return }

        switchDesktop(direction: scrollDelta > 0 ? .left : .right)
        lastScrollTime = now
    }

    private func switchDesktop(direction: Direction) {
        let keyCode: CGKeyCode = direction == .left ? 123 : 124 // Left / Right arrow
        guard let src = CGEventSource(stateID: .hidSystemState) else { return }
        if let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true),
           let up   = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) {
            down.flags.formUnion(.maskControl)
            up.flags.formUnion(.maskControl)
            down.post(tap: .cghidEventTap)
            usleep(1000)
            up.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Feature 2: ScrollFix
    // Assumes macOS Natural Scrolling is ON: keep the trackpad natural and
    // invert the classic mouse wheel. The source is distinguished via the
    // scroll event's "continuous" field (notched mouse = false, trackpad =
    // true) — so no Input Monitoring permission is required.
    private func applyScrollFix(_ event: CGEvent) {
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        guard !isContinuous else { return } // trackpad: leave untouched

        let dY = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let dX = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -dY)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: -dX)
    }

    // MARK: - Signals
    private func setupSignalHandler() {
        signal(SIGINT)  { _ in NSApp.terminate(nil) }
        signal(SIGTERM) { _ in NSApp.terminate(nil) }
    }
}

// MARK: - Entry point
final class MacUtilitiesApp: NSApplication {
    let utilities = MacUtilities()
    override func run() {
        utilities.start()
        super.run()
    }
}

let app = MacUtilitiesApp.shared
app.setActivationPolicy(.accessory) // Hide from the Dock
app.run()
