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
    public func copy(from sourceURL: URL, to targetURL: URL, targetBPM: BPM) throws -> TrackMetadataCopyResult {
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
            let copiedID3Tag = try copyID3Tag(
                from: sourceFile,
                to: targetFile,
                targetBPM: targetBPM
            )
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
                    to: targetFile,
                    targetBPM: targetBPM
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

    private func copyID3Tag(
        from sourceFile: AudioFileID,
        to targetFile: AudioFileID,
        targetBPM: BPM
    ) throws -> Bool {
        guard var id3Tag = try propertyData(kAudioFilePropertyID3Tag, from: sourceFile) else {
            return false
        }
        id3Tag = Self.updatedID3Tag(id3Tag, targetBPM: targetBPM.description)
        try writeUserData(id3Tag, chunkID: Self.id3ChunkID, index: 0, to: targetFile)
        return true
    }

    private func metadataChunkIDs(from sourceFile: AudioFileID) throws -> [UInt32] {
        guard let data = try propertyData(kAudioFilePropertyChunkIDs, from: sourceFile) else {
            return []
        }

        // `kAudioFilePropertyChunkIDs` can report one entry per chunk instance.
        // Dedupe so we don't process the same chunk type more than once (which
        // would duplicate every instance via AudioFileCountUserData).
        return data.withUnsafeBytes { rawBuffer in
            let ids = rawBuffer.bindMemory(to: UInt32.self)
            var seen: Set<UInt32> = []
            var result: [UInt32] = []
            for id in ids where Self.copyableMetadataChunkIDs.contains(id) && seen.insert(id).inserted {
                result.append(id)
            }
            return result
        }
    }

    private func copyUserDataChunk(
        _ chunkID: UInt32,
        from sourceFile: AudioFileID,
        to targetFile: AudioFileID,
        targetBPM: BPM
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
            data = Self.updatedMetadataChunk(
                data,
                chunkID: chunkID,
                targetBPM: targetBPM.description
            )

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

    private static func updatedMetadataChunk(_ data: Data, chunkID: UInt32, targetBPM: String) -> Data {
        if id3ChunkIDs.contains(chunkID) {
            return updatedID3Tag(data, targetBPM: targetBPM)
        }
        if chunkID == fourCC("LIST") {
            return updatedRIFFInfoList(data, targetBPM: targetBPM)
        }
        return data
    }

    private static func updatedID3Tag(_ tag: Data, targetBPM: String) -> Data {
        guard tag.count >= 10,
              String(bytes: tag[0..<3], encoding: .ascii) == "ID3" else {
            return tag
        }

        let version = tag[3]
        guard version == 2 || version == 3 || version == 4,
              let declaredBodySize = synchsafeUInt32(tag, at: 6) else {
            return tag
        }

        // Tag-level unsynchronisation rewrites byte values throughout the body
        // (every 0xFF gains a trailing 0x00). Parsing frames without un-syncing
        // would yield wrong frame sizes, so leave such tags untouched.
        if tag[5] & 0x80 != 0 {
            return tag
        }

        let bodyStart = 10
        let bodyEnd = min(tag.count, bodyStart + Int(declaredBodySize))
        guard bodyEnd >= bodyStart else {
            return tag
        }

        var cursor = bodyStart
        var body = Data()

        if version == 3 || version == 4,
           tag[5] & 0x40 != 0,
           let extendedHeaderSize = id3ExtendedHeaderSize(tag, version: version, at: cursor),
           cursor + extendedHeaderSize <= bodyEnd {
            body.append(tag[cursor..<(cursor + extendedHeaderSize)])
            cursor += extendedHeaderSize
        } else if (version == 3 || version == 4) && tag[5] & 0x40 != 0 {
            return tag
        }

        var updated = false
        while cursor < bodyEnd {
            let headerSize = version == 2 ? 6 : 10
            guard cursor + headerSize <= bodyEnd else {
                body.append(tag[cursor..<bodyEnd])
                break
            }

            if tag[cursor..<(cursor + headerSize)].allSatisfy({ $0 == 0 }) {
                body.append(tag[cursor..<bodyEnd])
                break
            }

            let frameIDLength = version == 2 ? 3 : 4
            guard let frameID = String(
                bytes: tag[cursor..<(cursor + frameIDLength)],
                encoding: .ascii
            ) else {
                return tag
            }

            let frameSize: Int?
            if version == 2 {
                frameSize = Int(uint24BE(tag, at: cursor + 3))
            } else if version == 4 {
                frameSize = synchsafeUInt32(tag, at: cursor + 4).map(Int.init)
            } else {
                frameSize = Int(uint32BE(tag, at: cursor + 4))
            }

            guard let frameSize,
                  frameSize >= 0,
                  cursor + headerSize + frameSize <= bodyEnd else {
                return tag
            }

            let payloadStart = cursor + headerSize
            let payloadEnd = payloadStart + frameSize
            let payload = Data(tag[payloadStart..<payloadEnd])

            let isBPMFrame = (version == 2 && frameID == "TBP")
                || (version != 2 && frameID == "TBPM")
            // For v2.3/v2.4, only rewrite when both frame-flag bytes are zero
            // — non-zero flags can indicate compression, encryption, grouping,
            // or a data-length indicator that our plain-text replacement would
            // silently invalidate.
            let frameFlagsClear = version == 2
                || (tag[cursor + 8] == 0 && tag[cursor + 9] == 0)

            if isBPMFrame && frameFlagsClear {
                let newPayload = updatedID3TextPayload(payload, value: targetBPM)
                appendID3Frame(
                    id: frameID,
                    payload: newPayload,
                    version: version,
                    originalHeader: tag[cursor..<(cursor + headerSize)],
                    to: &body
                )
                updated = true
            } else {
                body.append(tag[cursor..<payloadEnd])
            }

            cursor = payloadEnd
        }

        guard updated else {
            return tag
        }

        guard body.count <= 0x0fffffff else {
            return tag
        }

        var updatedTag = Data(tag[0..<10])
        writeSynchsafeUInt32(UInt32(body.count), to: &updatedTag, at: 6)
        updatedTag.append(body)
        if bodyEnd < tag.count {
            updatedTag.append(tag[bodyEnd..<tag.count])
        }
        return updatedTag
    }

    private static func updatedID3TextPayload(_ payload: Data, value: String) -> Data {
        let encoding = payload.first ?? 0x00
        var updated = Data([encoding])

        switch encoding {
        case 0x01:
            if payload.count >= 3 && payload[1] == 0xfe && payload[2] == 0xff {
                updated.append(contentsOf: [0xfe, 0xff])
                updated.append(value.data(using: .utf16BigEndian) ?? Data(value.utf8))
            } else {
                updated.append(contentsOf: [0xff, 0xfe])
                updated.append(value.data(using: .utf16LittleEndian) ?? Data(value.utf8))
            }
        case 0x02:
            updated.append(value.data(using: .utf16BigEndian) ?? Data(value.utf8))
        case 0x03:
            updated.append(contentsOf: value.utf8)
        default:
            updated[0] = 0x00
            updated.append(contentsOf: value.utf8)
        }

        return updated
    }

    private static func appendID3Frame(
        id: String,
        payload: Data,
        version: UInt8,
        originalHeader: Data.SubSequence,
        to output: inout Data
    ) {
        output.append(contentsOf: id.utf8)
        if version == 2 {
            appendUInt24BE(UInt32(payload.count), to: &output)
        } else {
            if version == 4 {
                appendSynchsafeUInt32(UInt32(payload.count), to: &output)
            } else {
                appendUInt32BE(UInt32(payload.count), to: &output)
            }
            output.append(originalHeader[(originalHeader.startIndex + 8)..<(originalHeader.startIndex + 10)])
        }
        output.append(payload)
    }

    private static func updatedRIFFInfoList(_ listData: Data, targetBPM: String) -> Data {
        guard listData.count >= 4,
              String(bytes: listData[0..<4], encoding: .ascii) == "INFO" else {
            return listData
        }

        var cursor = 4
        var updated = false
        var output = Data(listData[0..<4])

        while cursor + 8 <= listData.count {
            let chunkID = uint32BE(listData, at: cursor)
            let size = Int(uint32LE(listData, at: cursor + 4))
            let payloadStart = cursor + 8
            let payloadEnd = payloadStart + size
            guard payloadEnd <= listData.count else {
                return listData
            }

            let paddedEnd = payloadEnd + (size % 2)
            let nextCursor = min(paddedEnd, listData.count)

            if riffInfoBPMChunkIDs.contains(chunkID) {
                let originalPayload = listData[payloadStart..<payloadEnd]
                var newPayload = Data(targetBPM.utf8)
                if originalPayload.last == 0 {
                    newPayload.append(0)
                }
                appendUInt32BE(chunkID, to: &output)
                appendUInt32LE(UInt32(newPayload.count), to: &output)
                output.append(newPayload)
                if newPayload.count % 2 == 1 {
                    output.append(0)
                }
                updated = true
            } else {
                output.append(listData[cursor..<nextCursor])
            }

            cursor = nextCursor
        }

        if cursor < listData.count {
            output.append(listData[cursor..<listData.count])
        }

        return updated ? output : listData
    }

    private static func id3ExtendedHeaderSize(_ tag: Data, version: UInt8, at offset: Int) -> Int? {
        guard offset + 4 <= tag.count else {
            return nil
        }
        if version == 4 {
            guard let size = synchsafeUInt32(tag, at: offset), size >= 4 else {
                return nil
            }
            return Int(size)
        }

        let size = uint32BE(tag, at: offset)
        return Int(size) + 4
    }

    private static let id3ChunkID = fourCC("ID3 ")
    private static let id3LowercaseChunkID = fourCC("id3 ")
    private static let id3ChunkIDs: Set<UInt32> = [id3ChunkID, id3LowercaseChunkID]
    private static let riffInfoBPMChunkIDs: Set<UInt32> = [
        fourCC("IBPM"),
        fourCC("TBPM")
    ]

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

    private static func uint24BE(_ data: Data, at offset: Int) -> UInt32 {
        (UInt32(data[offset]) << 16) |
            (UInt32(data[offset + 1]) << 8) |
            UInt32(data[offset + 2])
    }

    private static func uint32BE(_ data: Data, at offset: Int) -> UInt32 {
        (UInt32(data[offset]) << 24) |
            (UInt32(data[offset + 1]) << 16) |
            (UInt32(data[offset + 2]) << 8) |
            UInt32(data[offset + 3])
    }

    private static func uint32LE(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) |
            (UInt32(data[offset + 1]) << 8) |
            (UInt32(data[offset + 2]) << 16) |
            (UInt32(data[offset + 3]) << 24)
    }

    private static func synchsafeUInt32(_ data: Data, at offset: Int) -> UInt32? {
        guard offset + 4 <= data.count else {
            return nil
        }
        let bytes = data[offset..<(offset + 4)]
        guard bytes.allSatisfy({ $0 & 0x80 == 0 }) else {
            return nil
        }
        return bytes.reduce(UInt32(0)) { result, byte in
            (result << 7) | UInt32(byte)
        }
    }

    private static func appendUInt24BE(_ value: UInt32, to data: inout Data) {
        data.append(UInt8((value >> 16) & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8(value & 0xff))
    }

    private static func appendUInt32BE(_ value: UInt32, to data: inout Data) {
        data.append(UInt8((value >> 24) & 0xff))
        data.append(UInt8((value >> 16) & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8(value & 0xff))
    }

    private static func appendUInt32LE(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8((value >> 16) & 0xff))
        data.append(UInt8((value >> 24) & 0xff))
    }

    private static func appendSynchsafeUInt32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8((value >> 21) & 0x7f))
        data.append(UInt8((value >> 14) & 0x7f))
        data.append(UInt8((value >> 7) & 0x7f))
        data.append(UInt8(value & 0x7f))
    }

    private static func writeSynchsafeUInt32(_ value: UInt32, to data: inout Data, at offset: Int) {
        data[offset] = UInt8((value >> 21) & 0x7f)
        data[offset + 1] = UInt8((value >> 14) & 0x7f)
        data[offset + 2] = UInt8((value >> 7) & 0x7f)
        data[offset + 3] = UInt8(value & 0x7f)
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
