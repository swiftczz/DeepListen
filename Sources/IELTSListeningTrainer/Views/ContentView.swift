import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var player: PlayerStore
    @AppStorage("themeColor") private var themeRawValue = ThemeColor.lime.rawValue
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var theme: ThemeColor {
        ThemeColor.color(for: themeRawValue)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 270, ideal: 310, max: 360)
        } detail: {
            PlayerDetailView()
        }
        .navigationTitle("IELTS Listening Trainer")
        .frame(minWidth: 960, minHeight: 640)
        .tint(theme.color)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 10) {
                Button {
                    player.showImportMediaPanel()
                } label: {
                    TitleBarIcon(systemImage: "plus")
                }
                .buttonStyle(TitleBarActionButtonStyle())
                .help("添加文件或目录")

                SettingsLink {
                    TitleBarIcon(systemImage: "gearshape")
                }
                .buttonStyle(TitleBarActionButtonStyle())
                .help("设置")
            }
            .padding(.top, 8)
            .padding(.trailing, 40)
            .offset(y: -52)
        }
    }
}

private struct TitleBarIcon: View {
    var systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 34, height: 34)
            .contentShape(Rectangle())
    }
}

private struct TitleBarActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(configuration.isPressed ? Color.secondary.opacity(0.18) : Color.white.opacity(0.96))
            )
            .shadow(
                color: configuration.isPressed ? .clear : Color.black.opacity(0.10),
                radius: configuration.isPressed ? 0 : 10,
                y: configuration.isPressed ? 0 : 5
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
