import Foundation

struct PlaybackFeedback: Equatable, Identifiable {
    enum Kind: Equatable {
        case skip(seconds: Int)
        case playbackMode(PlaybackMode)
        case playbackRate(Double)
    }

    let id = UUID()
    var kind: Kind
}
