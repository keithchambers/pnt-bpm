@preconcurrency import AVFoundation
import Foundation

public struct DetectedBPM: Equatable, Sendable {
    public let bpm: BPM
    /// Human-readable source: "id3 TBPM" or "filename".
    public let source: String

    public init(bpm: BPM, source: String) {
        self.bpm = bpm
        self.source = source
    }
}

/// Resolves the source BPM of a Beatport-purchased track when the user
/// omits `--source`. Beatport stores BPM in exactly two places:
///
///   1. An ID3v2 `TBPM` frame, embedded in the file's metadata
///      (an `ID3 ` chunk at the tail of an AIFF, or the ID3v2 header
///      of an MP3 download).
///   2. The filename, between double underscores:
///      `Artist_Title_(Mix)__<BPM>__<Key>.aiff`.
///
/// Detection is intentionally narrow — anything else returns nil and the
/// caller errors out. We do not guess from sibling files, parent
/// directories, generic metadata keys, or audio content.
public struct SourceBPMDetector {
    /// Plausible musical BPM window. Beatport's older AIFFs occasionally
    /// place a 7–8 digit track-ID in the `__N__` slot instead of a BPM
    /// (e.g. `__17628366__`); bounding rejects those false positives.
    public static let minPlausibleBPM: Double = 50
    public static let maxPlausibleBPM: Double = 220

    public init() {}

    public func detect(input: URL) -> DetectedBPM? {
        if let bpm = detectID3TBPM(input: input) {
            return DetectedBPM(bpm: bpm, source: "id3 TBPM")
        }
        let filename = input.deletingPathExtension().lastPathComponent
        if let bpm = Self.scanBeatportFilename(filename) {
            return DetectedBPM(bpm: bpm, source: "filename")
        }
        return nil
    }

    // MARK: - Beatport filename slot

    /// Matches the BPM Beatport writes between double underscores, e.g.
    /// `..._(Original_Mix)__125__Bb_Minor`.
    private static let filenamePattern = #"__(\d{2,3}(?:\.\d+)?)__"#

    static func scanBeatportFilename(_ string: String) -> BPM? {
        guard let regex = try? NSRegularExpression(pattern: filenamePattern) else { return nil }
        let nsRange = NSRange(string.startIndex..., in: string)
        guard let match = regex.firstMatch(in: string, range: nsRange),
              match.numberOfRanges >= 2,
              let captureRange = Range(match.range(at: 1), in: string),
              let value = Double(string[captureRange]),
              isPlausible(value) else {
            return nil
        }
        return try? BPM(value)
    }

    static func isPlausible(_ value: Double) -> Bool {
        value.isFinite && value >= minPlausibleBPM && value <= maxPlausibleBPM
    }

    // MARK: - ID3 TBPM

    private func detectID3TBPM(input: URL) -> BPM? {
        let asset = AVURLAsset(url: input)
        return runBlocking {
            do {
                let formats = try await asset.load(.availableMetadataFormats)
                for format in formats {
                    let items = try await asset.loadMetadata(for: format)
                    for item in items where Self.isTBPM(item) {
                        if let bpm = try await Self.bpmValue(from: item) {
                            return bpm
                        }
                    }
                }
            } catch {
                // Metadata read failures fall through to filename detection.
            }
            return nil
        }
    }

    private static func isTBPM(_ item: AVMetadataItem) -> Bool {
        if let key = item.key as? String, key.uppercased() == "TBPM" {
            return true
        }
        if let identifier = item.identifier?.rawValue,
           identifier.split(separator: "/").last?.uppercased() == "TBPM" {
            return true
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

    /// Bridge an async value-producing closure to a synchronous call so the
    /// CLI flow stays linear.
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
