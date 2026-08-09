import Foundation
import Observation

@MainActor
@Observable final class SubtitleSession {
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

    /// 字幕之间存在空档时继续沿用上一句，直到下一句真正开始。
    /// 第一条字幕开始前没有上一句，因此仍返回 nil。
    var sentenceLoopCue: SubtitleCue? {
        if let currentCue {
            return currentCue
        }

        if let nextIndex {
            guard nextIndex > cues.startIndex else { return nil }
            return cues[nextIndex - 1]
        }

        return cues.last
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

            if seconds < cue.start {
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
