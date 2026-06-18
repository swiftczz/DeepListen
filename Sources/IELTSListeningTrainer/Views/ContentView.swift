import SwiftUI

struct ContentView: View {
    @Environment(PlayerStore.self) private var player
    @AppStorage(AppThemeColor.storageKey) private var storedTheme = AppThemeColor.defaultTheme.rawValue
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showsMediaImporter = false
    @State private var showsThemePopover = false

    private let sidebarAutoHideWidth: CGFloat = 820

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
        .frame(minWidth: 800, minHeight: 640)
        .tint(theme.color)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { _, width in
            updateColumnVisibility(for: width)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showsMediaImporter = true
                } label: {
                    Label("添加音视频", systemImage: "plus")
                }
                .help("添加音视频")

                Button {
                    showsThemePopover.toggle()
                } label: {
                    Label("主题色", systemImage: "paintpalette")
                }
                .help("主题色")
                .popover(isPresented: $showsThemePopover, arrowEdge: .bottom) {
                    ThemeColorPopover(selection: themeSelection)
                }
            }
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

    private func updateColumnVisibility(for width: CGFloat) {
        let targetVisibility: NavigationSplitViewVisibility =
            width < sidebarAutoHideWidth ? .detailOnly : .all
        guard columnVisibility != targetVisibility else { return }
        columnVisibility = targetVisibility
    }
}
