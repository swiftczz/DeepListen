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
    @State private var playbackKeyboardMonitor = PlaybackKeyboardMonitor()
    @State private var sidebarWidth: CGFloat = 310
    @State private var windowSize = CGSize(width: 1180, height: 760)
    @State private var requestedWindowSize: CGSize?
    @FocusState private var isSidebarSearchFocused: Bool

    private let detailMinimumWidth: CGFloat = 480
    private let sidebarMinimumWidth: CGFloat = 270
    private let sidebarIdealWidth: CGFloat = 310
    private let sidebarMaximumWidth: CGFloat = 360
    private let sidebarAutoHideWidth: CGFloat = 800
    private let sidebarAutoShowWidth: CGFloat = 830

    private var windowMinimumWidth: CGFloat {
        guard columnVisibility != .detailOnly else {
            return detailMinimumWidth
        }

        return sidebarExpandedWindowWidth
    }

    private var sidebarExpandedWindowWidth: CGFloat {
        max(
            detailMinimumWidth + sidebarWidth,
            sidebarAutoHideWidth
        )
    }

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
                .navigationSplitViewColumnWidth(
                    min: sidebarMinimumWidth,
                    ideal: sidebarIdealWidth,
                    max: sidebarMaximumWidth
                )
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { _, width in
                    guard width >= sidebarMinimumWidth else { return }
                    sidebarWidth = width
                }
        } detail: {
            PlayerDetailView(theme: theme)
                .frame(minWidth: detailMinimumWidth)
        }
        .navigationSplitViewStyle(.prominentDetail)
        .navigationTitle("DeepListen")
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { _, size in
            windowSize = size
            guard requestedWindowSize == nil else { return }
            updateColumnVisibility(for: size.width)
        }
        .frame(minWidth: windowMinimumWidth, minHeight: 640)
        .frame(
            width: requestedWindowSize?.width,
            height: requestedWindowSize?.height
        )
        .windowResizeAnchor(.topLeading)
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
        .onAppear {
            playbackKeyboardMonitor.isEnabled = !isSidebarSearchFocused
            playbackKeyboardMonitor.start(player: player)
        }
        .onDisappear {
            playbackKeyboardMonitor.stop()
        }
        .onChange(of: isSidebarSearchFocused) { _, isFocused in
            playbackKeyboardMonitor.isEnabled = !isFocused
        }
        .focusedSceneValue(\.playbackCommandsEnabled, !isSidebarSearchFocused)
        .task(id: requestedWindowSize) {
            guard let requestedWindowSize else { return }

            try? await Task.sleep(for: .milliseconds(450))
            guard self.requestedWindowSize == requestedWindowSize else { return }
            self.requestedWindowSize = nil
        }
        .onChange(of: columnVisibility) { _, newVisibility in
            guard !isApplyingAutomaticColumnVisibility else {
                isApplyingAutomaticColumnVisibility = false
                return
            }

            if newVisibility == .detailOnly {
                userPrefersSidebarHidden = true
                requestedWindowSize = nil
            } else {
                userPrefersSidebarHidden = false
                if requestedWindowSize == nil {
                    requestWindowExpansionForSidebarIfNeeded()
                }
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

    @discardableResult
    private func requestWindowExpansionForSidebarIfNeeded() -> Bool {
        let targetWidth = sidebarExpandedWindowWidth
        guard windowSize.width + 0.5 < targetWidth else { return false }

        let startingSize = CGSize(
            width: max(windowSize.width, detailMinimumWidth),
            height: windowSize.height
        )
        let targetSize = CGSize(width: targetWidth, height: windowSize.height)
        requestedWindowSize = startingSize

        Task { @MainActor in
            await Task.yield()
            guard requestedWindowSize == startingSize else { return }

            withAnimation(.smooth(duration: 0.22)) {
                requestedWindowSize = targetSize
                columnVisibility = .all
            }
        }

        return true
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
