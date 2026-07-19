import Cocoa
import SwiftUI

/// Owns the menu bar item, the popover UI, and single-instance behavior.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let engine = FeatureEngine()

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
        let hosting = NSHostingController(rootView: MenuView())
        // Auto-size the popover to the SwiftUI content so it grows/shrinks as
        // rows appear (e.g. the mouse-button mapping pickers). Falls back to a
        // fixed size on older macOS.
        if #available(macOS 13.0, *) {
            hosting.sizingOptions = [.preferredContentSize]
        } else {
            popover.contentSize = NSSize(width: 300, height: 420)
        }
        popover.contentViewController = hosting
    }

    private static func statusBarIcon() -> NSImage {
        let candidates = ["computermouse", "cursorarrow.click.2", "arrow.up.arrow.down"]
        for name in candidates {
            if let img = NSImage(systemSymbolName: name, accessibilityDescription: "PC Mouse for Mac") {
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
