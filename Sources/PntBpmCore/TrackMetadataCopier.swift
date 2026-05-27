import AudioToolbox
import Foundation

public struct TrackMetadataCopyResult: Equatable {
    public let copiedChunks: [String]

    public var didCopyMetadata: Bool {
        !copiedChunks.isEmpty
    }

    public init(copiedChunks: [String]) {
        self.copiedChunks = copiedChunks
    }
}

public struct TrackMetadataCopier {
    public init() {}

    @discardableResult
    public func copy(from sourceURL: URL, to targetURL: URL) throws -> TrackMetadataCopyResult {
        var sourceFile: AudioFileID?
        var targetFile: AudioFileID?
        defer {
            if let sourceFile {
                AudioFileClose(sourceFile)
            }
            if let targetFile {
                AudioFileClose(targetFile)
            }
        }

        do {
            try openAudioFile(sourceURL, permission: .readPermission, into: &sourceFile)
            try openAudioFile(targetURL, permission: .readWritePermission, into: &targetFile)

            guard let sourceFile, let targetFile else {
                throw MetadataCopyError("could not open source or target audio file")
            }

            var copiedChunks: [String] = []
            let copiedID3Tag = try copyID3Tag(from: sourceFile, to: targetFile)
            if copiedID3Tag {
                copiedChunks.append(Self.fourCCString(Self.id3ChunkID))
            }

            for chunkID in try metadataChunkIDs(from: sourceFile) {
                if copiedID3Tag && Self.id3ChunkIDs.contains(chunkID) {
                    continue
                }

                let copiedCount = try copyUserDataChunk(
                    chunkID,
                    from: sourceFile,
                    to: targetFile
                )
                copiedChunks.append(
                    contentsOf: Array(repeating: Self.fourCCString(chunkID), count: copiedCount)
                )
            }

            return TrackMetadataCopyResult(copiedChunks: copiedChunks)
        } catch let error as MetadataCopyError {
            throw PntBpmError.metadataCopyFailed(sourceURL, targetURL, error.description)
        } catch {
            throw PntBpmError.metadataCopyFailed(sourceURL, targetURL, String(describing: error))
        }
    }

    private func openAudioFile(
        _ url: URL,
        permission: AudioFilePermissions,
        into fileID: inout AudioFileID?
    ) throws {
        let status = AudioFileOpenURL(url as CFURL, permission, 0, &fileID)
        try requireNoErr(status, "AudioFileOpenURL failed for \(url.path)")
    }

    private func copyID3Tag(from sourceFile: AudioFileID, to targetFile: AudioFileID) throws -> Bool {
        guard let id3Tag = try propertyData(kAudioFilePropertyID3Tag, from: sourceFile) else {
            return false
        }
        try writeUserData(id3Tag, chunkID: Self.id3ChunkID, index: 0, to: targetFile)
        return true
    }

    private func metadataChunkIDs(from sourceFile: AudioFileID) throws -> [UInt32] {
        guard let data = try propertyData(kAudioFilePropertyChunkIDs, from: sourceFile) else {
            return []
        }

        return data.withUnsafeBytes { rawBuffer in
            let ids = rawBuffer.bindMemory(to: UInt32.self)
            return ids.filter { Self.copyableMetadataChunkIDs.contains($0) }
        }
    }

    private func copyUserDataChunk(
        _ chunkID: UInt32,
        from sourceFile: AudioFileID,
        to targetFile: AudioFileID
    ) throws -> Int {
        var count: UInt32 = 0
        let countStatus = AudioFileCountUserData(sourceFile, chunkID, &count)
        if countStatus == kAudioFileInvalidChunkError {
            return 0
        }
        try requireNoErr(countStatus, "AudioFileCountUserData failed for \(Self.fourCCString(chunkID))")

        var copiedCount = 0
        for index in 0..<count {
            var size: UInt32 = 0
            let sizeStatus = AudioFileGetUserDataSize(sourceFile, chunkID, index, &size)
            try requireNoErr(sizeStatus, "AudioFileGetUserDataSize failed for \(Self.fourCCString(chunkID))")
            if size == 0 {
                continue
            }

            var data = Data(count: Int(size))
            let readStatus = data.withUnsafeMutableBytes { bytes in
                AudioFileGetUserData(sourceFile, chunkID, index, &size, bytes.baseAddress!)
            }
            try requireNoErr(readStatus, "AudioFileGetUserData failed for \(Self.fourCCString(chunkID))")

            if data.count != Int(size) {
                data.removeSubrange(Int(size)..<data.count)
            }

            try writeUserData(data, chunkID: chunkID, index: UInt32(copiedCount), to: targetFile)
            copiedCount += 1
        }

        return copiedCount
    }

    private func propertyData(_ propertyID: AudioFilePropertyID, from file: AudioFileID) throws -> Data? {
        var size: UInt32 = 0
        var writable: UInt32 = 0
        let infoStatus = AudioFileGetPropertyInfo(file, propertyID, &size, &writable)
        if infoStatus == kAudioFileUnsupportedPropertyError ||
            infoStatus == kAudioFileInvalidChunkError ||
            size == 0 {
            return nil
        }
        try requireNoErr(infoStatus, "AudioFileGetPropertyInfo failed for \(Self.fourCCString(propertyID))")

        var data = Data(count: Int(size))
        let readStatus = data.withUnsafeMutableBytes { bytes in
            AudioFileGetProperty(file, propertyID, &size, bytes.baseAddress!)
        }
        try requireNoErr(readStatus, "AudioFileGetProperty failed for \(Self.fourCCString(propertyID))")

        if data.count != Int(size) {
            data.removeSubrange(Int(size)..<data.count)
        }
        return data
    }

    private func writeUserData(
        _ data: Data,
        chunkID: UInt32,
        index: UInt32,
        to file: AudioFileID
    ) throws {
        guard data.count <= Int(UInt32.max) else {
            throw MetadataCopyError("metadata chunk \(Self.fourCCString(chunkID)) is too large")
        }

        let writeStatus = data.withUnsafeBytes { bytes in
            AudioFileSetUserData(
                file,
                chunkID,
                index,
                UInt32(data.count),
                bytes.baseAddress!
            )
        }
        try requireNoErr(writeStatus, "AudioFileSetUserData failed for \(Self.fourCCString(chunkID))")
    }

    private func requireNoErr(_ status: OSStatus, _ message: @autoclosure () -> String) throws {
        guard status == noErr else {
            throw MetadataCopyError("\(message()): \(Self.statusString(status))")
        }
    }

    private static let id3ChunkID = fourCC("ID3 ")
    private static let id3LowercaseChunkID = fourCC("id3 ")
    private static let id3ChunkIDs: Set<UInt32> = [id3ChunkID, id3LowercaseChunkID]

    private static let copyableMetadataChunkIDs: Set<UInt32> = [
        fourCC("ID3 "),
        fourCC("id3 "),
        fourCC("LIST"),
        fourCC("bext"),
        fourCC("iXML"),
        fourCC("axml"),
        fourCC("XMP "),
        fourCC("cart"),
        fourCC("cue "),
        fourCC("plst"),
        fourCC("adtl"),
        fourCC("labl"),
        fourCC("note"),
        fourCC("ltxt"),
        fourCC("smpl"),
        fourCC("inst"),
        fourCC("INST"),
        fourCC("MARK"),
        fourCC("COMT"),
        fourCC("NAME"),
        fourCC("AUTH"),
        fourCC("ANNO"),
        fourCC("(c) "),
        fourCC("APPL")
    ]

    private static func fourCC(_ string: String) -> UInt32 {
        precondition(string.utf8.count == 4, "fourCC values must be exactly four bytes")
        return string.utf8.reduce(UInt32(0)) { result, byte in
            (result << 8) | UInt32(byte)
        }
    }

    private static func fourCCString(_ value: UInt32) -> String {
        let bytes = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]
        if bytes.allSatisfy({ $0 >= 0x20 && $0 <= 0x7e }),
           let string = String(bytes: bytes, encoding: .ascii) {
            return string
        }
        return String(format: "0x%08x", value)
    }

    private static func statusString(_ status: OSStatus) -> String {
        let value = UInt32(bitPattern: status)
        let fourCC = fourCCString(value)
        if fourCC.hasPrefix("0x") {
            return "\(status)"
        }
        return "\(fourCC) (\(status))"
    }
}

private struct MetadataCopyError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
