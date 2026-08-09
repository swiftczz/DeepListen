import SwiftUI

struct ABLoopView: View {
    @Environment(PlayerStore.self) private var player

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        loopStatus
                        Spacer()
                        loopButtons
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        loopStatus
                        loopButtons
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("A/B 片段练习", systemImage: "repeat")
        }
    }

    private var loopStatus: some View {
        Text(player.loopSummary)
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    private var loopButtons: some View {
        HStack(spacing: 10) {
            Button {
                player.setSubtitleLooping(!player.isSubtitleLooping)
            } label: {
                Label("循环本句", systemImage: "repeat.1")
            }
            .disabled(player.subtitleForSentenceLoop == nil && !player.isSubtitleLooping)
            .help(player.isSubtitleLooping ? "停止循环本句" : "循环当前字幕句")
            .accessibilityValue(player.isSubtitleLooping ? "已开启" : "已关闭")
            .accessibilityHint("使用当前字幕的起止时间设置 A、B 点")

            Button {
                player.setLoopStart()
            } label: {
                Label("设 A", systemImage: "a.circle")
            }

            Button {
                player.setLoopEnd()
            } label: {
                Label("设 B", systemImage: "b.circle")
            }
            .disabled(player.loopStart == nil)

            Button {
                player.clearLoop()
            } label: {
                Label("清除", systemImage: "xmark.circle")
            }
            .disabled(player.loopStart == nil && player.loopEnd == nil)
        }
    }
}
