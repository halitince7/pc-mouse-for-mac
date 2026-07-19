import Foundation

enum Const {
    static let bundleID = "com.mathatinlabs.pcmouseformac"
    static let showUINotification = Notification.Name("com.mathatinlabs.pcmouseformac.showUI")

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}
