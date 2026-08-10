import Foundation
import Observation

@MainActor
@Observable final class SubtitleSession {
    /// 覆盖播放器时间基转换产生的亚帧级误差，不改变实际播放位置。
    private static let cueStartTolerance: TimeInterval = 0.005

    private(set) var cues: [SubtitleCue] = []
    private(set) var currentIndex: Int?
    private(set) var nextIndex: Int?
    private(set) var loadState: SubtitleLoadState = .idle

    var currentCue: SubtitleCue? {
        guard let currentIndex, cues.indices.contains(currentIndex) else { return nil }
        return cues[currentIndex]
    }

    var nextCue: SubtitleCue? {
        guard let nextIndex, cues.indices.contains(nextIndex) else { return nil }
        return cues[nextIndex]
    }

    /// 展示状态在句间空档继续沿用上一句，直到下一句真正开始。
    /// 这样上一句会保持放大和完整高亮，不会提前闪成下一句的灰色预览。
    var displayedIndex: Int? {
        if let currentIndex { return currentIndex }
        if let nextIndex {
            guard nextIndex > cues.startIndex else { return nil }
            return nextIndex - 1
        }
        return cues.indices.last
    }

    var displayedCue: SubtitleCue? {
        guard let displayedIndex, cues.indices.contains(displayedIndex) else { return nil }
        return cues[displayedIndex]
    }

    var sentenceLoopCue: SubtitleCue? {
        displayedCue
    }

    func beginLoading() {
        cues = []
        resetPosition()
        loadState = .loading
    }

    func markMissing() {
        cues = []
        resetPosition()
        loadState = .missing
    }

    func reset() {
        cues = []
        resetPosition()
        loadState = .idle
    }

    func apply(_ cues: [SubtitleCue], at seconds: TimeInterval) {
        self.cues = cues
        loadState = cues.isEmpty ? .failed : .loaded
        updatePosition(at: seconds)
    }

    func updatePosition(at seconds: TimeInterval) {
        guard !cues.isEmpty else {
            resetPosition()
            return
        }

        let position = position(at: seconds)
        if currentIndex != position.current {
            currentIndex = position.current
        }
        if nextIndex != position.next {
            nextIndex = position.next
        }
    }

    private func position(at seconds: TimeInterval) -> (current: Int?, next: Int?) {
        var lowerBound = cues.startIndex
        var upperBound = cues.endIndex

        while lowerBound < upperBound {
            let middleIndex = lowerBound + (upperBound - lowerBound) / 2
            let cue = cues[middleIndex]

            if seconds < cue.start - Self.cueStartTolerance {
                upperBound = middleIndex
            } else if seconds > cue.end {
                lowerBound = middleIndex + 1
            } else {
                let nextIndex = cues.indices.contains(middleIndex + 1)
                    ? middleIndex + 1
                    : nil
                return (middleIndex, nextIndex)
            }
        }

        let nextIndex = cues.indices.contains(lowerBound) ? lowerBound : nil
        return (nil, nextIndex)
    }

    private func resetPosition() {
        currentIndex = nil
        nextIndex = nil
    }
}
