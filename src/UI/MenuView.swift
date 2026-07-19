import SwiftUI
import AppKit

/// The popover panel shown from the menu bar icon.
struct MenuView: View {
    @ObservedObject var settings = AppSettings.shared
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
                FeatureRow(
                    icon: "arrow.up.arrow.down",
                    title: "Smooth Scrolling",
                    subtitle: "Glide the mouse wheel like a trackpad",
                    isOn: $settings.smoothScrolling)
                FeatureRow(
                    icon: "computermouse.fill",
                    title: "Mouse Buttons",
                    subtitle: "Remap the side (thumb) buttons",
                    isOn: $settings.mouseButtons)
                // Always rendered (dimmed when off) so toggling never resizes
                // the popover — a resize makes it jump away from the menu bar.
                VStack(spacing: 8) {
                    ButtonMapRow(label: "Back button", selection: $settings.backButtonAction)
                    ButtonMapRow(label: "Forward button", selection: $settings.forwardButtonAction)
                }
                .padding(.leading, 33)
                .disabled(!settings.mouseButtons)
                .opacity(settings.mouseButtons ? 1 : 0.4)
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
                Text("PC Mouse for Mac").font(.system(size: 14, weight: .semibold))
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
                Text("Enable PC Mouse for Mac to activate the features.")
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

struct ButtonMapRow: View {
    let label: String
    @Binding var selection: ButtonAction

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 12)).foregroundColor(.secondary)
            Spacer()
            Picker("", selection: $selection) {
                ForEach(ButtonAction.allCases) { action in
                    Text(action.title).tag(action)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .fixedSize()
        }
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
