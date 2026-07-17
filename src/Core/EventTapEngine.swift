import Cocoa

/// Core engine: a single CGEvent tap that dispatches scroll/flag events to the
/// enabled features. One process, one permission (Accessibility).
final class FeatureEngine: NSObject {
    private var ctrlPressed = false
    private var lastScrollTime: TimeInterval = 0
    private let scrollCooldown: TimeInterval = 0.2

    private var eventTap: CFMachPort?
    private var retryTimer: Timer?

    private let settings = AppSettings.shared
    private let scrollDir = ScrollDirectionMonitor.shared
    private let smoothScroller = SmoothScroller()

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
                }
            }
        }
    }

    private func setupTapIfPossible() {
        guard eventTap == nil, AXIsProcessTrusted() else { return }

        let eventMask = (1 << CGEventType.scrollWheel.rawValue)
                      | (1 << CGEventType.flagsChanged.rawValue)
                      | (1 << CGEventType.otherMouseDown.rawValue)
                      | (1 << CGEventType.otherMouseUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (_, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let mySelf = Unmanaged<FeatureEngine>.fromOpaque(refcon).takeUnretainedValue()
                return mySelf.handleEvent(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    // MARK: Event dispatch
    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .flagsChanged:
            ctrlPressed = event.flags.contains(.maskControl)

        case .scrollWheel:
            // Our own synthetic smooth-scroll events: let them pass untouched.
            if smoothScroller.isSynthetic(event) {
                return Unmanaged.passUnretained(event)
            }
            // Feature 1: Ctrl + scroll switches desktops (consumes the event).
            if ctrlPressed && settings.desktopSwitcher {
                handleDesktopSwitch(event)
                return nil
            }

            let isMouse = event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0

            // Feature 3: Smooth scrolling (mouse wheel only). Takes over the
            // mouse scroll, applying the ScrollFix direction itself.
            if isMouse && settings.smoothScrolling {
                let invert = settings.scrollFix && scrollDir.naturalScrollingOn
                let sign = invert ? -1.0 : 1.0
                let dY = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
                let dX = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
                smoothScroller.enqueue(lineDeltaY: dY * sign, lineDeltaX: dX * sign)
                return nil // consume the original chunky notch
            }

            // Feature 2: ScrollFix (direction only, no smoothing).
            if settings.scrollFix {
                applyScrollFix(event)
            }

        case .otherMouseDown, .otherMouseUp:
            // Feature 4: Mouse side-button remapping.
            if settings.mouseButtons {
                let button = event.getIntegerValueField(.mouseEventButtonNumber)
                if let action = action(forButton: button), action != .none {
                    if type == .otherMouseDown { perform(action) }
                    return nil // consume both down and up so the default doesn't fire
                }
            }

        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }

        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }

    // MARK: Feature 1 — Desktop Switcher
    private enum Direction { case left, right }

    private func handleDesktopSwitch(_ event: CGEvent) {
        let scrollDelta = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let now = CACurrentMediaTime()
        guard now - lastScrollTime > scrollCooldown, scrollDelta != 0 else { return }
        switchDesktop(direction: scrollDelta > 0 ? .left : .right)
        lastScrollTime = now
    }

    private func switchDesktop(direction: Direction) {
        postControlKey(direction == .left ? 123 : 124) // Ctrl + Left / Right arrow
    }

    // MARK: Feature 4 — Mouse side-button remapping
    // Typical mice deliver the thumb buttons as "other" mouse buttons:
    // 3 = back, 4 = forward.
    private func action(forButton button: Int64) -> ButtonAction? {
        switch button {
        case 3: return settings.backButtonAction
        case 4: return settings.forwardButtonAction
        default: return nil
        }
    }

    private func perform(_ action: ButtonAction) {
        if let key = action.key { postControlKey(key) }
    }

    // MARK: Shared — synthesize a Control + <key> shortcut
    private func postControlKey(_ keyCode: CGKeyCode) {
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

    // MARK: Feature 2 — ScrollFix
    // Goal (independent of the system Natural Scrolling setting):
    //   mouse  -> traditional   |   trackpad -> natural
    // The device is inferred from the scroll event's "continuous" field
    // (notched mouse wheel = false, trackpad = true), so no Input Monitoring
    // permission is required.
    private func applyScrollFix(_ event: CGEvent) {
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let isMouse = !isContinuous
        let naturalOn = scrollDir.naturalScrollingOn

        // Mouse wants traditional; trackpad wants natural.
        let shouldInvert = isMouse ? naturalOn : !naturalOn
        guard shouldInvert else { return }

        let dY = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let dX = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -dY)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: -dX)

        // For continuous (trackpad / precision) input, also invert the smooth
        // pixel deltas so scrolling stays fluid.
        if isContinuous {
            let pY = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
            let pX = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
            let fY = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
            let fX = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: -pY)
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: -pX)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -fY)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -fX)
        }
    }
}
