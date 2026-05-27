@preconcurrency import AVFoundation
import Foundation

public struct DetectedBPM: Equatable, Sendable {
    public let bpm: BPM
    /// Human-readable source: "metadata id3", "filename", "parent dir: foo-...".
    public let source: String

    public init(bpm: BPM, source: String) {
        self.bpm = bpm
        self.source = source
    }
}

public struct SourceBPMDetector {
    /// Plausible musical BPM window. Filenames sometimes contain track IDs or
    /// release dates in the same slot — bounding the value rejects those.
    public static let minPlausibleBPM: Double = 50
    public static let maxPlausibleBPM: Double = 220

    public init() {}

    /// Resolve the source BPM of `input` by trying, in order:
    ///   1. Embedded audio-file metadata (ID3 TBPM, iTunes tmpo, ...).
    ///   2. The input filename (Beatport `__BPM__`, trailing `-BPM`).
    ///   3. Up to 3 ancestor directory names (handles mvsep nested layout).
    /// Returns nil if no plausible BPM can be inferred.
    public func detect(input: URL) -> DetectedBPM? {
        if let detected = detectFromMetadata(input: input) {
            return detected
        }

        let filename = input.deletingPathExtension().lastPathComponent
        if let bpm = Self.scanForBPM(in: filename) {
            return DetectedBPM(bpm: bpm, source: "filename")
        }

        var directory = input.deletingLastPathComponent()
        for _ in 0..<3 {
            let name = directory.lastPathComponent
            if name.isEmpty || name == "/" { break }
            if let bpm = Self.scanForBPM(in: name) {
                return DetectedBPM(bpm: bpm, source: "parent dir: \(name)")
            }
            directory = directory.deletingLastPathComponent()
        }

        return nil
    }

    // MARK: - Filename scanning

    /// Patterns are evaluated in order; first plausible capture wins.
    private static let filenamePatterns: [String] = [
        // Beatport: ..._(Original_Mix)__125__F_Minor
        #"__(\d{2,3}(?:\.\d+)?)__"#,
        // mvsep / dash-separated: ...-original-mix-125-bb-minor
        // (allows up to 3 short suffix tokens, e.g. "g-mi", "bb-minor")
        #"[-_](\d{2,3}(?:\.\d+)?)(?:[-_][A-Za-z#]{1,8}){0,3}$"#
    ]

    static func scanForBPM(in string: String) -> BPM? {
        for pattern in filenamePatterns {
            if let value = firstCaptureDouble(of: pattern, in: string),
               isPlausible(value),
               let bpm = try? BPM(value) {
                return bpm
            }
        }
        return nil
    }

    private static func firstCaptureDouble(of pattern: String, in string: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(string.startIndex..., in: string)
        guard let match = regex.firstMatch(in: string, range: nsRange),
              match.numberOfRanges >= 2,
              let captureRange = Range(match.range(at: 1), in: string) else {
            return nil
        }
        return Double(string[captureRange])
    }

    static func isPlausible(_ value: Double) -> Bool {
        value.isFinite && value >= minPlausibleBPM && value <= maxPlausibleBPM
    }

    // MARK: - Metadata

    private func detectFromMetadata(input: URL) -> DetectedBPM? {
        let asset = AVURLAsset(url: input)
        return runBlocking {
            do {
                let formats = try await asset.load(.availableMetadataFormats)
                for format in formats {
                    let items = try await asset.loadMetadata(for: format)
                    for item in items {
                        guard Self.isBPMKey(item) else { continue }
                        if let value = try await Self.bpmValue(from: item) {
                            return DetectedBPM(bpm: value, source: "metadata \(format.rawValue)")
                        }
                    }
                }
            } catch {
                // Metadata reads can fail (corrupt, missing chunks) — fall through to filename.
            }
            return nil
        }
    }

    private static func isBPMKey(_ item: AVMetadataItem) -> Bool {
        if let key = item.commonKey?.rawValue.lowercased(), key.contains("bpm") {
            return true
        }
        if let key = item.key as? String {
            let lowered = key.lowercased()
            if lowered.contains("bpm") || lowered == "tmpo" || lowered == "tbpm" {
                return true
            }
        }
        if let identifier = item.identifier?.rawValue.lowercased() {
            if identifier.contains("bpm") || identifier.hasSuffix("tmpo") || identifier.hasSuffix("tbpm") {
                return true
            }
        }
        return false
    }

    private static func bpmValue(from item: AVMetadataItem) async throws -> BPM? {
        if let number = try await item.load(.numberValue)?.doubleValue, isPlausible(number) {
            return try? BPM(number)
        }
        if let string = try await item.load(.stringValue),
           let number = Double(string.trimmingCharacters(in: .whitespacesAndNewlines)),
           isPlausible(number) {
            return try? BPM(number)
        }
        return nil
    }

    /// Bridge an async value-producing closure to a synchronous call.
    /// The detector keeps a sync API so the CLI flow stays linear.
    private func runBlocking<T: Sendable>(_ work: @escaping @Sendable () async -> T) -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let box = AsyncResultBox<T>()
        Task.detached {
            let value = await work()
            box.set(value)
            semaphore.signal()
        }
        semaphore.wait()
        return box.value!
    }
}

private final class AsyncResultBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T?

    var value: T? { lock.withLock { stored } }

    func set(_ value: T) { lock.withLock { stored = value } }
}
