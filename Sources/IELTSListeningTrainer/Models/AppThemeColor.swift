import SwiftUI

enum AppThemeColor: String, CaseIterable, Identifiable {
    case system
    case blue
    case purple
    case pink
    case red
    case orange
    case yellow
    case green
    case graphite

    static let storageKey = "appThemeColor"
    static let defaultTheme: AppThemeColor = .system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "系统"
        case .blue:
            return "蓝色"
        case .purple:
            return "紫色"
        case .pink:
            return "粉色"
        case .red:
            return "红色"
        case .orange:
            return "橙色"
        case .yellow:
            return "黄色"
        case .green:
            return "绿色"
        case .graphite:
            return "石墨色"
        }
    }

    var color: Color {
        switch self {
        case .system:
            return Color(nsColor: .controlAccentColor)
        case .blue:
            return Color(nsColor: .systemBlue)
        case .purple:
            return Color(nsColor: .systemPurple)
        case .pink:
            return Color(nsColor: .systemPink)
        case .red:
            return Color(nsColor: .systemRed)
        case .orange:
            return Color(nsColor: .systemOrange)
        case .yellow:
            return Color(nsColor: .systemYellow)
        case .green:
            return Color(nsColor: .systemGreen)
        case .graphite:
            return Color(nsColor: .systemGray)
        }
    }

    var selectionForegroundColor: Color {
        switch self {
        case .yellow:
            return .black.opacity(0.82)
        default:
            return .white
        }
    }

    init(storedValue: String) {
        self = AppThemeColor(rawValue: storedValue) ?? Self.defaultTheme
    }
}
