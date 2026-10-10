import Foundation

/// Periodically checks free disk space on the volume that holds the clip output
/// folder and reports a low-storage warning message (or nil) through `onChange`.
@MainActor
final class StorageMonitor {
    private enum Constants {
        static let thresholdBytes: Int64 = 5 * 1024 * 1024 * 1024
        static let refreshIntervalNanos: UInt64 = 30 * 1_000_000_000
    }

    /// Free bytes on the volume holding the clip output folder and on the volume
    /// holding the live recording segments (nil when unknown).
    struct Sample: Sendable {
        var output: Int64?
        var scratch: Int64?
    }

    private let sampler: @Sendable () -> Sample
    private let onChange: @MainActor (String?) -> Void
    private var task: Task<Void, Never>?
    private var hasReported = false
    private var lastWarning: String?

    init(
        sampler: @escaping @Sendable () -> Sample = StorageMonitor.liveSample,
        onChange: @escaping @MainActor (String?) -> Void
    ) {
        self.sampler = sampler
        self.onChange = onChange
    }

    deinit {
        task?.cancel()
    }

    func start() {
        refresh()
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Constants.refreshIntervalNanos)
                if Task.isCancelled { break }
                self?.refresh()
            }
        }
    }

    /// Volume capacity queries go through a system service and take ~40 ms each, so
    /// they run off the main thread. The result is only published when it changes:
    /// every publish re-renders the menu, and most checks find nothing new.
    func refresh() {
        let sampler = sampler
        Task.detached(priority: .utility) { [weak self] in
            let sample = sampler()
            let warning = Self.warning(outputFreeBytes: sample.output, scratchFreeBytes: sample.scratch)
            await self?.apply(warning)
        }
    }

    private func apply(_ warning: String?) {
        guard !hasReported || warning != lastWarning else { return }
        hasReported = true
        lastWarning = warning
        onChange(warning)
    }

    nonisolated static func liveSample() -> Sample {
        let output = ClipStorageLocation.current()
        let scratch = FileManager.default.temporaryDirectory
        let outputFree = availableBytes(forFolder: output)
        // Usually the same volume: ask once instead of twice.
        let scratchFree = sameVolume(output, scratch) ? outputFree : availableBytes(forFolder: scratch)
        return Sample(output: outputFree, scratch: scratchFree)
    }

    nonisolated static func sameVolume(_ a: URL, _ b: URL) -> Bool {
        func identifier(_ url: URL) -> NSObject? {
            let existing = nearestExistingDirectory(url)
            return (try? existing.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? NSObject
        }
        guard let first = identifier(a), let second = identifier(b) else { return false }
        return first.isEqual(second)
    }

    /// Clips are exported to the output folder, but the rolling live segments (up
    /// to five minutes of video) are written to the temporary directory, which is
    /// usually the system volume. Either one running out of space breaks recording.
    nonisolated static func warning(outputFreeBytes: Int64?, scratchFreeBytes: Int64?) -> String? {
        if let free = outputFreeBytes, free < Constants.thresholdBytes {
            return "Low disk space: \(ByteCountFormatter.string(fromByteCount: free, countStyle: .file)) left."
        }
        if let free = scratchFreeBytes, free < Constants.thresholdBytes {
            return "Low disk space for live recording: \(ByteCountFormatter.string(fromByteCount: free, countStyle: .file)) left on the system volume."
        }
        return nil
    }

    nonisolated static func availableBytes(forFolder folder: URL) -> Int64? {
        let fileManager = FileManager.default
        let targetURL = nearestExistingDirectory(folder)

        if let resourceValues = try? targetURL.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ]) {
            if let availableForImportantUsage = resourceValues.volumeAvailableCapacityForImportantUsage {
                return availableForImportantUsage
            }
            if let availableCapacity = resourceValues.volumeAvailableCapacity {
                return Int64(availableCapacity)
            }
        }

        if let attributes = try? fileManager.attributesOfFileSystem(forPath: targetURL.path),
            let freeSize = attributes[.systemFreeSize] as? NSNumber
        {
            return freeSize.int64Value
        }

        return nil
    }

    /// the output folder may not exist yet, but free space is a property of the
    /// volume, so any existing ancestor on that volume gives the right answer
    nonisolated private static func nearestExistingDirectory(_ url: URL) -> URL {
        let fileManager = FileManager.default
        var candidate = url.standardizedFileURL
        while !fileManager.fileExists(atPath: candidate.path) {
            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path { break }
            candidate = parent
        }
        return candidate
    }
}
