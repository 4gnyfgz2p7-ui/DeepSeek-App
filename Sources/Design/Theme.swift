import SwiftUI

enum Theme {
    static let background = Color(hex: 0x0A0A0B)
    static let surface = Color(hex: 0x161619)
    static let surfaceRaised = Color(hex: 0x232327)
    static let bubble = Color(hex: 0x2A2A2E)
    static let accent = Color(hex: 0x4D6BFE)
    static let text = Color(hex: 0xEDEDF0)
    static let secondaryText = Color(hex: 0x8B8B92)
    static let tertiaryText = Color(hex: 0x61616A)
    static let danger = Color(hex: 0xFF6B6B)
    static let hairline = Color.white.opacity(0.07)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

struct CircleIconButton: View {
    var systemName: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.text)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Theme.surfaceRaised))
        }
        .buttonStyle(.plain)
    }
}

struct ToggleChip: View {
    var title: String
    var systemName: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { isOn.toggle() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: systemName)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(isOn ? Theme.accent : Theme.tertiaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(isOn ? Theme.accent.opacity(0.14) : Color.white.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
    }
}
