import SwiftUI

struct ABLoopView: View {
    @Environment(PlayerStore.self) private var player
    var theme: AppThemeColor

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

                if let loopStart = player.loopStart {
                    loopMarkers(loopStart: loopStart)
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

    private func loopMarkers(loopStart: TimeInterval) -> some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(theme.color)
                .frame(width: 22, height: 6)
                .accessibilityHidden(true)

            Text("A \(loopStart.formattedPlaybackTime)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let loopEnd = player.loopEnd {
                Text("B \(loopEnd.formattedPlaybackTime)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(loopAccessibilityLabel(loopStart: loopStart))
    }

    private func loopAccessibilityLabel(loopStart: TimeInterval) -> String {
        if let loopEnd = player.loopEnd {
            return "A 点 \(loopStart.formattedPlaybackTime)，B 点 \(loopEnd.formattedPlaybackTime)"
        }
        return "A 点 \(loopStart.formattedPlaybackTime)"
    }
}
