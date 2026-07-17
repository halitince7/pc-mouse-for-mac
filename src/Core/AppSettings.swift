import Foundation
import Combine

/// Persisted feature toggles, shared across the engine and the UI.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let store = UserDefaults.standard

    @Published var desktopSwitcher: Bool { didSet { store.set(desktopSwitcher, forKey: "desktopSwitcher") } }
    @Published var scrollFix: Bool { didSet { store.set(scrollFix, forKey: "scrollFix") } }
    @Published var smoothScrolling: Bool { didSet { store.set(smoothScrolling, forKey: "smoothScrolling") } }
    @Published var mouseButtons: Bool { didSet { store.set(mouseButtons, forKey: "mouseButtons") } }
    @Published var backButtonAction: ButtonAction { didSet { store.set(backButtonAction.rawValue, forKey: "backButtonAction") } }
    @Published var forwardButtonAction: ButtonAction { didSet { store.set(forwardButtonAction.rawValue, forKey: "forwardButtonAction") } }

    private init() {
        store.register(defaults: [
            "desktopSwitcher": true, "scrollFix": true, "smoothScrolling": true,
            "mouseButtons": false,
            "backButtonAction": ButtonAction.desktopLeft.rawValue,
            "forwardButtonAction": ButtonAction.desktopRight.rawValue,
        ])
        desktopSwitcher = store.bool(forKey: "desktopSwitcher")
        scrollFix = store.bool(forKey: "scrollFix")
        smoothScrolling = store.bool(forKey: "smoothScrolling")
        mouseButtons = store.bool(forKey: "mouseButtons")
        backButtonAction = ButtonAction(rawValue: store.string(forKey: "backButtonAction") ?? "") ?? .desktopLeft
        forwardButtonAction = ButtonAction(rawValue: store.string(forKey: "forwardButtonAction") ?? "") ?? .desktopRight
    }
}
