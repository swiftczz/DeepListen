import SwiftUI

enum ThemeColor: String, CaseIterable, Identifiable {
    case lime
    case blue
    case teal
    case purple
    case orange
    case pink

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lime:
            return "青绿"
        case .blue:
            return "蓝色"
        case .teal:
            return "湖蓝"
        case .purple:
            return "紫色"
        case .orange:
            return "橙色"
        case .pink:
            return "粉色"
        }
    }

    var color: Color {
        switch self {
        case .lime:
            return Color(red: 0.23, green: 0.96, blue: 0.34)
        case .blue:
            return Color(red: 0.18, green: 0.48, blue: 0.95)
        case .teal:
            return Color(red: 0.04, green: 0.66, blue: 0.62)
        case .purple:
            return Color(red: 0.55, green: 0.34, blue: 0.95)
        case .orange:
            return Color(red: 0.95, green: 0.49, blue: 0.18)
        case .pink:
            return Color(red: 0.93, green: 0.25, blue: 0.55)
        }
    }

    static func color(for rawValue: String) -> ThemeColor {
        ThemeColor(rawValue: rawValue) ?? .lime
    }
}
