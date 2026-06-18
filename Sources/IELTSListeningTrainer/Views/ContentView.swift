import SwiftUI

struct ContentView: View {
    @Environment(PlayerStore.self) private var player
    @AppStorage(AppThemeColor.storageKey) private var storedTheme = AppThemeColor.defaultTheme.rawValue
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showsMediaImporter = false
    @State private var showsThemePopover = false

    private var theme: AppThemeColor {
        AppThemeColor(storedValue: storedTheme)
    }

    private var themeSelection: Binding<AppThemeColor> {
        Binding {
            AppThemeColor(storedValue: storedTheme)
        } set: { newValue in
            storedTheme = newValue.rawValue
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(theme: theme)
                .navigationSplitViewColumnWidth(min: 270, ideal: 310, max: 360)
        } detail: {
            PlayerDetailView(theme: theme)
        }
        .navigationTitle("IELTS Listening Trainer")
        .frame(minWidth: 960, minHeight: 640)
        .tint(theme.color)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
                TitlebarActionButton(systemImage: "plus", label: "添加音视频") {
                    showsMediaImporter = true
                }

                TitlebarActionButton(systemImage: "paintpalette", label: "主题色") {
                    showsThemePopover.toggle()
                }
                .popover(isPresented: $showsThemePopover, arrowEdge: .bottom) {
                    ThemeColorPopover(selection: themeSelection)
                }
            }
            .padding(.top, -42)
            .padding(.trailing, 42)
        }
        .fileImporter(
            isPresented: $showsMediaImporter,
            allowedContentTypes: PlayerStore.importableContentTypes,
            allowsMultipleSelection: true
        ) { result in
            if case let .success(urls) = result {
                player.openExternalURLs(urls)
            }
        }
        .overlay(alignment: .top) {
            if let libraryNotice = player.libraryNotice {
                Label(libraryNotice, systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
                    .padding(.top, 18)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: player.libraryNotice)
    }
}

private struct TitlebarActionButton: View {
    var systemImage: String
    var label: String
    var action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 30, height: 28)
        }
        .buttonStyle(TitlebarActionButtonStyle(isHovered: isHovered))
        .controlSize(.small)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct TitlebarActionButtonStyle: ButtonStyle {
    var isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? Color.primary : Color.secondary)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            }
            .shadow(
                color: .black.opacity(configuration.isPressed ? 0.08 : (isHovered ? 0.10 : 0.16)),
                radius: configuration.isPressed ? 2 : (isHovered ? 5 : 10),
                y: configuration.isPressed ? 1 : (isHovered ? 2 : 4)
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPressed {
            return Color.secondary.opacity(0.18)
        }

        if isHovered {
            return Color.secondary.opacity(0.12)
        }

        return Color.clear
    }
}
