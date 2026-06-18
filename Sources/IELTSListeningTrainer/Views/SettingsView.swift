import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var player: PlayerStore
    @AppStorage("themeColor") private var themeRawValue = ThemeColor.lime.rawValue

    private var theme: ThemeColor {
        ThemeColor.color(for: themeRawValue)
    }

    var body: some View {
        Form {
            Section("外观") {
                Picker("主题色", selection: $themeRawValue) {
                    ForEach(ThemeColor.allCases) { themeColor in
                        Text(themeColor.title).tag(themeColor.rawValue)
                    }
                }

                HStack(spacing: 12) {
                    ForEach(ThemeColor.allCases) { themeColor in
                        Button {
                            themeRawValue = themeColor.rawValue
                        } label: {
                            Circle()
                                .fill(themeColor.color)
                                .frame(width: 24, height: 24)
                                .overlay {
                                    if themeColor == theme {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .help(themeColor.title)
                    }
                }
            }

            Section("媒体库") {
                Button {
                    player.reloadDefaultLibrary()
                } label: {
                    Label("重新载入内置音频", systemImage: "arrow.clockwise")
                }

                Button(role: .destructive) {
                    player.clearLibrary()
                } label: {
                    Label("清空列表", systemImage: "trash")
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 430, height: 300)
    }
}
