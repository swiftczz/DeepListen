import SwiftUI

struct ThemeColorPopover: View {
    @Binding var selection: AppThemeColor

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("主题色")
                .font(.headline)

            HStack(spacing: 10) {
                ForEach(AppThemeColor.allCases) { theme in
                    Button {
                        selection = theme
                    } label: {
                        ThemeSwatch(theme: theme, isSelected: selection == theme)
                    }
                    .buttonStyle(.plain)
                    .help(theme.title)
                    .accessibilityLabel(theme.title)
                    .accessibilityValue(selection == theme ? "已选择" : "未选择")
                }
            }
        }
        .padding(16)
    }
}

private struct ThemeSwatch: View {
    var theme: AppThemeColor
    var isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.secondary.opacity(isSelected ? 0.18 : 0.10))
                .frame(width: 34, height: 34)

            swatch
                .frame(width: 24, height: 24)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.72), lineWidth: 1)
                }

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.selectionForegroundColor)
                    .shadow(color: .black.opacity(0.22), radius: 1, y: 1)
            }
        }
        .contentShape(Circle())
    }

    @ViewBuilder
    private var swatch: some View {
        if theme == .system {
            Circle()
                .fill(
                    AngularGradient(
                        colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
                        center: .center
                    )
                )
        } else {
            Circle()
                .fill(theme.color)
        }
    }
}
