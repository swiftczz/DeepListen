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
