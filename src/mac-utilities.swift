#!/usr/bin/swift

import Cocoa
import SwiftUI
import Foundation

// MARK: - Constants
enum Const {
    static let bundleID = "com.mathatinlabs.macutilities"
    static let showUINotification = Notification.Name("com.mathatinlabs.macutilities.showUI")
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

// MARK: - Settings (persisted feature toggles)
final class Settings: ObservableObject {
    static let shared = Settings()
    private let store = UserDefaults.standard

    @Published var desktopSwitcher: Bool { didSet { store.set(desktopSwitcher, forKey: "desktopSwitcher") } }
    @Published var scrollFix: Bool { didSet { store.set(scrollFix, forKey: "scrollFix") } }

    private init() {
        store.register(defaults: ["desktopSwitcher": true, "scrollFix": true])
        desktopSwitcher = store.bool(forKey: "desktopSwitcher")
        scrollFix = store.bool(forKey: "scrollFix")
    }
}

// MARK: - System natural-scrolling monitor
// Reads the global macOS "Natural Scrolling" setting so ScrollFix works the
// same regardless of how the user has it configured. macOS applies ONE global
// direction to both mouse and trackpad; we read it and invert the right device
// to always land on: mouse = traditional, trackpad = natural.
final class ScrollDirectionMonitor {
    static let shared = ScrollDirectionMonitor()
    private(set) var naturalScrollingOn = true
    private var timer: Timer?

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func refresh() {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        var exists: DarwinBoolean = false
        let value = CFPreferencesGetAppBooleanValue(
            "com.apple.swipescrolldirection" as CFString,
            kCFPreferencesAnyApplication, &exists)
        // macOS default (when unset) is natural scrolling ON.
        naturalScrollingOn = exists.boolValue ? value : true
    }
}

// MARK: - Accessibility permission monitor (drives the UI banner)
final class PermissionMonitor: ObservableObject {
    static let shared = PermissionMonitor()
    @Published var trusted: Bool = AXIsProcessTrusted()
    private var timer: Timer?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            let now = AXIsProcessTrusted()
            if now != self?.trusted { self?.trusted = now }
        }
    }
}

// MARK: - Core engine (event tap)
final class MacUtilities: NSObject {
    private var ctrlPressed = false
    private var lastScrollTime: TimeInterval = 0
    private let scrollCooldown: TimeInterval = 0.2

    private var eventTap: CFMachPort?
    private var retryTimer: Timer?

    private let settings = Settings.shared
    private let scrollDir = ScrollDirectionMonitor.shared

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

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (_, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let mySelf = Unmanaged<MacUtilities>.fromOpaque(refcon).takeUnretainedValue()
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
            // Feature 1: Ctrl + scroll switches desktops (consumes the event).
            if ctrlPressed && settings.desktopSwitcher {
                handleDesktopSwitch(event)
                return nil
            }
            // Feature 2: ScrollFix.
            if settings.scrollFix {
                applyScrollFix(event)
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

// MARK: - SwiftUI menu content
struct MenuView: View {
    @ObservedObject var settings = Settings.shared
    @ObservedObject var permission = PermissionMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if !permission.trusted {
                permissionBanner
                Divider()
            }
            VStack(spacing: 12) {
                FeatureRow(
                    icon: "rectangle.on.rectangle.angled",
                    title: "Desktop Switcher",
                    subtitle: "Hold Ctrl and scroll to switch desktops",
                    isOn: $settings.desktopSwitcher)
                FeatureRow(
                    icon: "computermouse",
                    title: "ScrollFix",
                    subtitle: "Traditional mouse · natural trackpad",
                    isOn: $settings.scrollFix)
            }
            .padding(14)
            Divider()
            footer
        }
        .frame(width: 300)
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("Mac Utilities").font(.system(size: 14, weight: .semibold))
                Text("Version \(Const.version)")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(14)
    }

    private var permissionBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility permission needed")
                    .font(.system(size: 12, weight: .medium))
                Text("Enable Mac Utilities to activate the features.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
            Button("Open") { openAccessibilitySettings() }
                .controlSize(.small)
        }
        .padding(12)
        .background(Color.orange.opacity(0.10))
    }

    private var footer: some View {
        HStack {
            Button(action: openAccessibilitySettings) {
                Label("Accessibility", systemImage: "gearshape")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(14)
    }

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(isOn ? .accentColor : .secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(subtitle).font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
    }
}

// MARK: - App delegate (menu bar + popover)
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let engine = MacUtilities()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single instance: if another copy is already running (e.g. the login
        // agent), ask it to show its UI and quit this one. This is what makes
        // clicking the app in Finder open the panel instead of doing nothing.
        let current = NSRunningApplication.current
        let duplicates = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == Const.bundleID && $0.processIdentifier != current.processIdentifier
        }
        if !duplicates.isEmpty {
            DistributedNotificationCenter.default().postNotificationName(
                Const.showUINotification, object: nil, userInfo: nil, deliverImmediately: true)
            NSApp.terminate(nil)
            return
        }

        engine.start()
        ScrollDirectionMonitor.shared.start()
        PermissionMonitor.shared.start()
        setupStatusItem()
        setupPopover()

        // Allow other launches (Finder double-click) to reopen the panel.
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(showFromNotification),
            name: Const.showUINotification, object: nil)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = Self.statusBarIcon()
            button.action = #selector(togglePopover)
            button.target = self
        }
    }

    private func setupPopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 300, height: 260)
        popover.contentViewController = NSHostingController(rootView: MenuView())
    }

    private static func statusBarIcon() -> NSImage {
        let candidates = ["computermouse", "cursorarrow.click.2", "arrow.up.arrow.down"]
        for name in candidates {
            if let img = NSImage(systemSymbolName: name, accessibilityDescription: "Mac Utilities") {
                img.isTemplate = true
                return img
            }
        }
        let fallback = NSApp.applicationIconImage.copy() as! NSImage
        fallback.size = NSSize(width: 18, height: 18)
        return fallback
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc private func showFromNotification() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.popover.isShown else { return }
            self.togglePopover()
        }
    }
}

// MARK: - Entry point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // Menu bar app: no Dock icon
app.run()
