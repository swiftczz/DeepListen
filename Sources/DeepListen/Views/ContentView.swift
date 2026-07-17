import SwiftUI

struct ContentView: View {
    @Environment(PlayerStore.self) private var player
    @AppStorage(AppThemeColor.storageKey) private var storedTheme = AppThemeColor.defaultTheme.rawValue
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var userPrefersSidebarHidden = false
    @State private var isApplyingAutomaticColumnVisibility = false
    @State private var showsMediaImporter = false
    @State private var showsThemePopover = false
    @State private var isDropTargeted = false
    @FocusState private var isSidebarSearchFocused: Bool

    private let sidebarAutoHideWidth: CGFloat = 820
    private let sidebarAutoShowWidth: CGFloat = 860

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
            SidebarView(theme: theme, searchFocus: $isSidebarSearchFocused)
                .navigationSplitViewColumnWidth(min: 270, ideal: 310, max: 360)
        } detail: {
            PlayerDetailView(theme: theme)
        }
        .navigationTitle("DeepListen")
        .frame(minWidth: 800, minHeight: 640)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .tint(theme.color)
        .dropDestination(for: URL.self) { urls, _ in
            guard !urls.isEmpty else { return false }
            player.openExternalURLs(urls)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(theme.color, lineWidth: 3)
                    .padding(3)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: isDropTargeted)
        .focusedSceneValue(\.playbackCommandsEnabled, !isSidebarSearchFocused)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { _, width in
            updateColumnVisibility(for: width)
        }
        .onChange(of: columnVisibility) { _, newVisibility in
            guard !isApplyingAutomaticColumnVisibility else {
                isApplyingAutomaticColumnVisibility = false
                return
            }

            switch newVisibility {
            case .all:
                userPrefersSidebarHidden = false
            case .detailOnly:
                userPrefersSidebarHidden = true
            default:
                break
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showsMediaImporter = true
                } label: {
                    Label(
                        player.isImporting ? "正在导入" : "添加音视频",
                        systemImage: player.isImporting
                            ? "arrow.triangle.2.circlepath"
                            : "plus"
                    )
                }
                .help(player.isImporting ? "正在导入音视频" : "添加音视频")
                .disabled(player.isImporting)

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
            switch result {
            case let .success(urls):
                player.openExternalURLs(urls)
            case let .failure(error):
                player.reportImportFailure(error)
            }
        }
        .overlay(alignment: .top) {
            if let libraryNotice = player.libraryNotice {
                Label(libraryNotice.message, systemImage: libraryNotice.systemImage)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(noticeColor(for: libraryNotice))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
                    .padding(.top, 18)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(libraryNotice.message)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: player.libraryNotice)
    }

    private func updateColumnVisibility(for width: CGFloat) {
        if width < sidebarAutoHideWidth {
            applyAutomaticColumnVisibility(.detailOnly)
        } else if width > sidebarAutoShowWidth, !userPrefersSidebarHidden {
            applyAutomaticColumnVisibility(.all)
        }
    }

    private func applyAutomaticColumnVisibility(_ visibility: NavigationSplitViewVisibility) {
        guard columnVisibility != visibility else { return }
        isApplyingAutomaticColumnVisibility = true
        columnVisibility = visibility
    }

    private func noticeColor(for notice: LibraryNotice) -> Color {
        switch notice.kind {
        case .success:
            return .primary
        case .warning:
            return .orange
        case .failure:
            return .red
        }
    }
}
