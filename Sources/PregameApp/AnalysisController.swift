import Foundation
import PregameCore
import SwiftUI

/// Analyses a document's tracks in the background (cached results are instant)
/// and writes key/BPM back into the project as they finish.
@MainActor
final class AnalysisController: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var done = 0
    @Published private(set) var total = 0
    @Published private(set) var current = ""
    @Published private(set) var failures: [String] = []

    private var task: Task<Void, Never>?

    var progress: Double { total == 0 ? 0 : Double(done) / Double(total) }

    /// Try the tracks that failed again (their files may have been found).
    func retryFailed(in document: MixDocument) {
        failures = []
        analyseMissing(in: document)
    }

    /// Analyse every track that has no analysis yet.
    func analyseMissing(in document: MixDocument) {
        // Missing, or cached by an older analysis version (re-analysed for structure).
        let pending = document.project.tracks
            .filter { $0.analysedKey == nil || $0.analysedBpm == nil
                      || $0.contentHash.flatMap(AnalysisCache.shared.cached) == nil }
            .filter { !failures.contains($0.filename) }
        guard !pending.isEmpty, !running else { return }
        running = true
        done = 0
        total = pending.count
        task = Task { [weak self] in
            let workers = max(1, ProcessInfo.processInfo.activeProcessorCount - 2)
            await withTaskGroup(of: (UUID, String, String?, TrackAnalysis?).self) { group in
                var queue = pending[...]
                func enqueue() {
                    guard let t = queue.popFirst() else { return }
                    group.addTask {
                        await Task.detached(priority: .userInitiated) {
                            do {
                                let hash = try AnalysisCache.contentHash(t.url)
                                let fresh = AnalysisCache.shared.cached(hash) == nil
                                let started = Date()
                                let a = try AnalysisCache.shared.analysis(for: t.url, hash: hash)
                                if fresh {
                                    Telemetry.shared.record(.trackAnalysed(seconds: Date().timeIntervalSince(started),
                                                                           trackSeconds: a.duration))
                                }
                                return (t.id, t.filename, hash, a)
                            } catch {
                                return (t.id, t.filename, nil, nil)
                            }
                        }.value
                    }
                }
                for _ in 0..<workers { enqueue() }
                for await (id, name, hash, analysis) in group {
                    guard let self else { return }
                    self.current = name
                    self.done += 1
                    if let hash, let analysis {
                        document.silently { p in
                            if let i = p.tracks.firstIndex(where: { $0.id == id }) {
                                p.tracks[i].apply(analysis, hash: hash)
                            }
                        }
                    } else {
                        self.failures.append(name)
                    }
                    enqueue()
                }
            }
            self?.running = false
            self?.current = ""
        }
    }
}
