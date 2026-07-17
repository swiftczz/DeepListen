import Foundation

struct LibraryNotice: Equatable {
    enum Kind: Equatable {
        case success
        case warning
        case failure
    }

    var message: String
    var kind: Kind

    var systemImage: String {
        switch kind {
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .failure:
            return "xmark.octagon.fill"
        }
    }
}
