import AppKit
import SwiftUI

enum NotchTheme: String, CaseIterable, Identifiable {
    case blue, orange, purple, pink, mint, neutral
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var nsColor: NSColor {
        switch self {
        case .blue: return NSColor(srgbRed: 0.30, green: 0.64, blue: 1, alpha: 1)
        case .orange: return NSColor(srgbRed: 1, green: 0.61, blue: 0.27, alpha: 1)
        case .purple: return NSColor(srgbRed: 0.72, green: 0.52, blue: 1, alpha: 1)
        case .pink: return NSColor(srgbRed: 1, green: 0.48, blue: 0.70, alpha: 1)
        case .mint: return NSColor(srgbRed: 0.39, green: 0.87, blue: 0.71, alpha: 1)
        case .neutral: return NSColor(white: 0.85, alpha: 1)
        }
    }
    var color: Color { Color(nsColor: nsColor) }
}

struct ThemeSwatches: View {
    @Binding var selection: NotchTheme
    var body: some View {
        HStack(spacing: 8) {
            Text("Theme").foregroundStyle(.gray)
            Spacer()
            ForEach(NotchTheme.allCases) { theme in
                Button { selection = theme } label: {
                    Circle().fill(theme.color).frame(width: 12, height: 12)
                        .padding(3)
                        .overlay(Circle().stroke(selection == theme ? theme.color : .clear, lineWidth: 1.5))
                        .frame(width: 22, height: 22).contentShape(Circle())
                }.buttonStyle(.plain).help(theme.title)
                    .accessibilityLabel("\(theme.title) theme")
                    .accessibilityAddTraits(selection == theme ? .isSelected : [])
            }
        }
    }
}

/// Native macOS switches may retain system green despite SwiftUI's tint.
struct ThemeSwitchStyle: ToggleStyle {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                configuration.isOn.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                configuration.label
                Spacer(minLength: 4)
                Capsule().fill(configuration.isOn ? color : Color.white.opacity(0.18))
                    .frame(width: 28, height: 16)
                    .overlay {
                        Circle().fill(.white).frame(width: 12, height: 12)
                            .offset(x: configuration.isOn ? 6 : -6)
                    }
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}
