import CoreGraphics

/// Actions a remapped mouse button can trigger. Each maps to a system key
/// combination that is synthesized when the button is pressed.
enum ButtonAction: String, CaseIterable, Identifiable {
    case none
    case desktopLeft
    case desktopRight
    case missionControl
    case appWindows

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:           return "None"
        case .desktopLeft:    return "Desktop Left"
        case .desktopRight:   return "Desktop Right"
        case .missionControl: return "Mission Control"
        case .appWindows:     return "App Windows"
        }
    }

    /// The key to synthesize (all use the Control modifier), or nil for `.none`.
    var key: CGKeyCode? {
        switch self {
        case .none:           return nil
        case .desktopLeft:    return 123 // Ctrl + Left
        case .desktopRight:   return 124 // Ctrl + Right
        case .missionControl: return 126 // Ctrl + Up
        case .appWindows:     return 125 // Ctrl + Down
        }
    }
}
