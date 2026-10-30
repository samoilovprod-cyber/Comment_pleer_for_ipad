import SwiftUI

/// Тёмная палитра в духе сервисов видео-ревью: видео в центре, интерфейс не спорит с картинкой.
enum Theme {
    static let background = Color(hex: 0x1E2029)
    static let panel = Color(hex: 0x2A2D3A)
    static let sidebar = Color(hex: 0x252733)
    static let field = Color(hex: 0x353847)
    static let separator = Color.white.opacity(0.08)
    static let accent = Color(hex: 0xA98BE0)
    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.55)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Плашка с тайм-кодом — в списке комментариев и в поле ввода.
struct TimecodeChip: View {
    let text: String
    var isProminent = false

    var body: some View {
        Text(text)
            .font(.caption.monospacedDigit().weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .foregroundStyle(isProminent ? Color.white : Theme.textPrimary)
            .background(isProminent ? Theme.accent : Theme.field, in: RoundedRectangle(cornerRadius: 4))
    }
}
