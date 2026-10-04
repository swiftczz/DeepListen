import AVFoundation
import Foundation

enum MediaDurationLoader {
    nonisolated static func loadDuration(for url: URL) async -> TimeInterval? {
        // Do not extract every MKV during library import. Selected tracks prepare their audio on demand.
        guard let playbackURL = try? MediaPlaybackPreparer().cachedPlaybackURL(for: url) else {
            return nil
        }
        let asset = AVURLAsset(url: playbackURL)
        guard let duration = try? await asset.load(.duration) else { return nil }
        let seconds = duration.seconds
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }
}
