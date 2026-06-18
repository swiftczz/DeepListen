import Foundation

enum PlaybackMode: String, CaseIterable, Identifiable {
    case sequence
    case singleLoop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sequence:
            return "顺序播放"
        case .singleLoop:
            return "单曲循环"
        }
    }


    var systemImage: String {
        switch self {
        case .sequence:
            return "list.bullet"
        case .singleLoop:
            return "repeat.1"
        }
    }
}
