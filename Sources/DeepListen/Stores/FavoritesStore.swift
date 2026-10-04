import Foundation
import Observation

@MainActor
@Observable final class FavoritesStore {
    private(set) var passages: [SavedPassage]
    var workspace: ListeningWorkspace = .library
    var selectedID: UUID?
    var searchText = ""
    var blindReview: Bool { didSet { defaults.set(blindReview, forKey: "favoritesBlindReview") } }
    private(set) var isReviewing = false
    private(set) var isReviewComplete = false
    private(set) var isRevealed = false
    private(set) var reviewQueue: [UUID] = []
    private(set) var reviewedCount = 0
    @ObservationIgnored private let defaults: UserDefaults
    private static let storageKey = "savedPassages.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        passages = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([SavedPassage].self, from: $0) }?
            .filter(\.isValid) ?? []
        blindReview = defaults.object(forKey: "favoritesBlindReview") as? Bool ?? true
        selectedID = passages.first?.id
    }

    var selected: SavedPassage? { passages.first { $0.id == selectedID } }
    var pendingCount: Int { passages.filter { !$0.isMastered }.count }
    var hidesAnswer: Bool { isReviewing && blindReview && !isRevealed }
    var visiblePassages: [SavedPassage] {
        passages.filter { passage in
            searchText.isEmpty || [passage.text, passage.sourceTitle, passage.note, passage.translation ?? ""]
                .contains { $0.localizedStandardContains(searchText) }
        }
    }

    func saved(_ candidate: SavedPassage?) -> SavedPassage? {
        guard let candidate else { return nil }
        return passages.first { $0.matches(candidate) }
    }

    @discardableResult func add(_ candidate: SavedPassage) -> UUID? {
        guard candidate.isValid else { return nil }
        if let existing = saved(candidate) { return existing.id }
        passages.insert(candidate, at: 0)
        if selectedID == nil { selectedID = candidate.id }
        persist()
        return candidate.id
    }

    func remove(_ id: UUID) {
        passages.removeAll { $0.id == id }
        reviewQueue.removeAll { $0 == id }
        if selectedID == id {
            selectedID = isReviewing ? reviewQueue.first : visiblePassages.first?.id
        }
        if isReviewing && reviewQueue.isEmpty { finishReview() }
        persist()
    }

    func updateNote(_ note: String, for id: UUID) {
        guard let index = passages.firstIndex(where: { $0.id == id }) else { return }
        passages[index].note = note
        persist()
    }

    func setMastered(_ mastered: Bool, for id: UUID) {
        guard let index = passages.firstIndex(where: { $0.id == id }) else { return }
        passages[index].isMastered = mastered
        passages[index].lastReviewedAt = Date()
        persist()
    }

    func relink(_ id: UUID, to url: URL) {
        guard let passage = passages.first(where: { $0.id == id }), PlayerStore.isPlayableMediaURL(url) else { return }
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        for index in passages.indices where passages[index].sourcePath == passage.sourcePath {
            passages[index].sourcePath = path
            passages[index].sourceTitle = ListeningTrack(url: url).title
        }
        persist()
    }

    func startReview() {
        reviewQueue = visiblePassages.filter { !$0.isMastered }.map(\.id)
        reviewedCount = 0
        isReviewComplete = false
        isReviewing = !reviewQueue.isEmpty
        isRevealed = false
        if let first = reviewQueue.first { selectedID = first }
    }

    func selectAdjacent(_ offset: Int) {
        let visible = visiblePassages
        guard !visible.isEmpty else { return }
        let current = visible.firstIndex { $0.id == selectedID } ?? 0
        selectedID = visible[min(max(current + offset, 0), visible.count - 1)].id
    }

    func reveal() { isRevealed = true }
    func repeatCurrent() { isRevealed = false }

    func advance(mastered: Bool) {
        guard isReviewing, let id = selectedID else { return }
        if mastered { setMastered(true, for: id); reviewedCount += 1 }
        reviewQueue.removeAll { $0 == id }
        isRevealed = false
        if let next = reviewQueue.first { selectedID = next }
        else { finishReview() }
    }

    func stopReview() {
        isReviewing = false
        isReviewComplete = false
        isRevealed = false
        reviewQueue = []
    }

    private func finishReview() {
        isReviewing = false
        isReviewComplete = true
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(passages) { defaults.set(data, forKey: Self.storageKey) }
    }
}
