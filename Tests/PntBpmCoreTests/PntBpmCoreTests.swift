import Foundation
import Testing
@testable import PntBpmCore

@Test func parsesCommaSeparatedTargets() throws {
    let targets = try parseBPMList(["125,122,120"])
    #expect(targets.map(\.value) == [125, 122, 120])
}

@Test func parsesRepeatedTargets() throws {
    let command = try CLIParser.parse([
        "pnt-bpm",
        "song.wav",
        "--source",
        "128",
        "--target",
        "125",
        "--output",
        "122,120"
    ])

    guard case .render(let options) = command else {
        Issue.record("expected render command")
        return
    }

    #expect(options.source?.value == 128)
    #expect(options.targets.map(\.value) == [125, 122, 120])
}

@Test func computesSeratoTimeAndDurationRatios() throws {
    let source = try BPM(120)
    let target = try BPM(128)
    let ratios = TempoRatios(source: source, target: target)

    #expect(abs(ratios.seratoTime - 1.0666666667) < 0.0000001)
    #expect(abs(ratios.outputDurationRatio - 0.9375) < 0.0000001)
}

@Test func rendersOutputNameTemplate() throws {
    let name = OutputPlanner.renderName(
        template: "{title}_{bpm}bpm.{ext}",
        title: "song",
        bpm: "125",
        ext: "wav"
    )

    #expect(name == "song_125bpm.wav")
}

@Test func dryRunPlansDefaultToInputDirectory() throws {
    let input = URL(fileURLWithPath: "/tmp/song.aiff")
    let plans = try OutputPlanner.plans(
        input: input,
        source: try BPM(120),
        targets: [try BPM(125), try BPM(128)],
        outDir: nil,
        format: "wav",
        nameTemplate: "{title}_{bpm}bpm.{ext}"
    )

    #expect(plans.map { $0.outputURL.path } == [
        "/tmp/song_125bpm.wav",
        "/tmp/song_128bpm.wav"
    ])
}

@Test func rejectsMissingTargets() {
    #expect(throws: PntBpmError.missingTargets) {
        _ = try CLIParser.parse(["pnt-bpm", "song.wav", "--source", "120"])
    }
}

@Test func rejectsMP3Inputs() {
    #expect(throws: PntBpmError.unsupportedInputFormat(URL(fileURLWithPath: "/tmp/song.mp3"))) {
        _ = try CLIParser.parse([
            "pnt-bpm",
            "/tmp/song.mp3",
            "--source",
            "120",
            "--target",
            "125"
        ])
    }

    #expect(throws: PntBpmError.unsupportedInputFormat(URL(fileURLWithPath: "/tmp/song.MP3"))) {
        _ = try CLIParser.parse([
            "pnt-bpm",
            "--input",
            "/tmp/song.MP3",
            "--source",
            "120",
            "--target",
            "125"
        ])
    }
}

@Test func parsesMultiplePositionalInputs() throws {
    let command = try CLIParser.parse([
        "pnt-bpm",
        "a.wav",
        "b.aiff",
        "c.wav",
        "--source",
        "128",
        "--target",
        "125,122"
    ])

    guard case .render(let options) = command else {
        Issue.record("expected render command")
        return
    }

    #expect(options.inputs.map(\.lastPathComponent) == ["a.wav", "b.aiff", "c.wav"])
    #expect(options.targets.map(\.value) == [125, 122])
}

@Test func parsesRepeatedInputFlag() throws {
    let command = try CLIParser.parse([
        "pnt-bpm",
        "-i",
        "a.wav",
        "--input",
        "b.wav",
        "c.wav",
        "--source",
        "128",
        "--target",
        "125"
    ])

    guard case .render(let options) = command else {
        Issue.record("expected render command")
        return
    }

    #expect(options.inputs.map(\.lastPathComponent) == ["a.wav", "b.wav", "c.wav"])
}

@Test func rejectsCopyMetadataFlagBecauseMetadataCopyIsAutomatic() {
    #expect(throws: PntBpmError.invalidOption("--copy-metadata")) {
        _ = try CLIParser.parse([
            "pnt-bpm",
            "song.wav",
            "--source",
            "128",
            "--target",
            "125",
            "--copy-metadata"
        ])
    }
}

@Test func renderOptionsKeepsSingleInputInitializerCompatibility() throws {
    let options = RenderOptions(
        input: URL(fileURLWithPath: "/tmp/song.wav"),
        source: try BPM(128),
        targets: [try BPM(125)]
    )

    #expect(options.input.path == "/tmp/song.wav")
    #expect(options.inputs.map(\.path) == ["/tmp/song.wav"])
}

@Test func multiInputPlansFanOutOverInputsAndTargets() throws {
    let plans = try OutputPlanner.plans(
        inputs: [
            URL(fileURLWithPath: "/tmp/a.wav"),
            URL(fileURLWithPath: "/tmp/b.aiff")
        ],
        source: try BPM(120),
        targets: [try BPM(125), try BPM(128)],
        outDir: nil,
        format: "wav",
        nameTemplate: "{title}_{bpm}bpm.{ext}"
    )

    #expect(plans.map { $0.outputURL.path } == [
        "/tmp/a_125bpm.wav",
        "/tmp/a_128bpm.wav",
        "/tmp/b_125bpm.wav",
        "/tmp/b_128bpm.wav"
    ])
}

@Test func multiInputPlansSupportPerInputSource() throws {
    let plans = try OutputPlanner.plans(
        inputs: [
            (URL(fileURLWithPath: "/tmp/a.wav"), try BPM(120)),
            (URL(fileURLWithPath: "/tmp/b.aiff"), try BPM(128))
        ],
        targets: [try BPM(125)],
        outDir: nil,
        format: "wav",
        nameTemplate: "{title}_{bpm}bpm.{ext}"
    )

    #expect(plans.map(\.source.value) == [120, 128])
    #expect(plans.map { $0.outputURL.path } == [
        "/tmp/a_125bpm.wav",
        "/tmp/b_125bpm.wav"
    ])
}

@Test func multiInputPlansShareOutDir() throws {
    let plans = try OutputPlanner.plans(
        inputs: [
            URL(fileURLWithPath: "/songs/a.wav"),
            URL(fileURLWithPath: "/other/b.wav")
        ],
        source: try BPM(120),
        targets: [try BPM(125)],
        outDir: URL(fileURLWithPath: "/renders"),
        format: "wav",
        nameTemplate: "{title}_{bpm}bpm.{ext}"
    )

    #expect(plans.map { $0.outputURL.path } == [
        "/renders/a_125bpm.wav",
        "/renders/b_125bpm.wav"
    ])
}

@Test func rejectsCollidingOutputsAcrossInputs() {
    #expect(throws: PntBpmError.outputCollision(URL(fileURLWithPath: "/renders/song_125bpm.wav"))) {
        _ = try OutputPlanner.plans(
            inputs: [
                URL(fileURLWithPath: "/a/song.wav"),
                URL(fileURLWithPath: "/b/song.aiff")
            ],
            source: try BPM(120),
            targets: [try BPM(125)],
            outDir: URL(fileURLWithPath: "/renders"),
            format: "wav",
            nameTemplate: "{title}_{bpm}bpm.{ext}"
        )
    }
}

@Test func rejectsEmptyInputs() {
    #expect(throws: PntBpmError.missingInput) {
        _ = try OutputPlanner.plans(
            inputs: [],
            source: try BPM(120),
            targets: [try BPM(125)],
            outDir: nil,
            format: "wav",
            nameTemplate: "{title}_{bpm}bpm.{ext}"
        )
    }
}

@Test func rejectsUnsupportedFormat() throws {
    #expect(throws: PntBpmError.unsupportedFormat("mp3")) {
        _ = try OutputPlanner.plans(
            input: URL(fileURLWithPath: "/tmp/song.wav"),
            source: try BPM(120),
            targets: [try BPM(125)],
            outDir: nil,
            format: "mp3",
            nameTemplate: "{title}_{bpm}bpm.{ext}"
        )
    }
}

@Test func sourceIsOptionalWhenAutoDetectIntended() throws {
    let command = try CLIParser.parse([
        "pnt-bpm",
        "song.aiff",
        "--target",
        "125"
    ])
    guard case .render(let options) = command else {
        Issue.record("expected render command")
        return
    }
    #expect(options.source == nil)
    #expect(options.targets.map(\.value) == [125])
}

@Test func detectsBeatportFilenameBPM() {
    let bpm = SourceBPMDetector.scanBeatportFilename(
        "Andrew_Meller_Bee_(Original_Mix)__125__Bb_Minor"
    )
    #expect(bpm?.value == 125)
}

@Test func detectsAIFFID3TBPMBeforeFilenameFallback() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("pnt-bpm-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let url = directory.appendingPathComponent(
        "Andrew_Meller_Bee_(Original_Mix)__17628366__Bb_Minor.aiff"
    )
    try makeAIFFWithID3TBPM("124").write(to: url)

    let detected = SourceBPMDetector().detect(input: url)
    #expect(detected?.bpm == (try BPM(124)))
    #expect(detected?.source == "id3 TBPM")
}

@Test func ignoresBeatportTrackIdInBPMSlot() {
    // Older Beatport AIFFs used a 7–8 digit track ID in the same slot.
    let bpm = SourceBPMDetector.scanBeatportFilename(
        "Emi_Galvan_Samsara_(Original_Mix)__17628366__E_Major"
    )
    #expect(bpm == nil)
}

@Test func ignoresNonBeatportFilenames() {
    // mvsep / dash-separated names are explicitly out of scope.
    #expect(SourceBPMDetector.scanBeatportFilename("technasia-i-am-somebody-original-mix-125") == nil)
    #expect(SourceBPMDetector.scanBeatportFilename("andrew-meller-bee-original-mix-125-bb-minor") == nil)
    // Bare numeric values in the filename without the __BPM__ wrapper are ignored.
    #expect(SourceBPMDetector.scanBeatportFilename("song_125bpm") == nil)
}

@Test func doesNotWalkParentDirectories() {
    // The detector must look at the file itself, not its containing folder.
    let url = URL(fileURLWithPath: "/tmp/somefolder-mix-125/vocals.wav")
    let detected = SourceBPMDetector().detect(input: url)
    #expect(detected == nil)
}

@Test func copiesID3MetadataAndArtworkToRenderedWAVAndUpdatesBPM() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("pnt-bpm-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let source = directory.appendingPathComponent("source.aiff")
    let target = directory.appendingPathComponent("target.wav")
    let artwork = Data([0xff, 0xd8, 0xff, 0xd9])
    let id3Tag = makeID3v23Tag(frames: [
        makeID3v23TextFrame(id: "TIT2", value: "Source Track"),
        makeID3v23TextFrame(id: "TPE1", value: "Source Artist"),
        makeID3v23TextFrame(id: "TBPM", value: "99"),
        makeID3v23ArtworkFrame(mimeType: "image/jpeg", data: artwork)
    ])

    try makeAIFFWithID3Tag(id3Tag).write(to: source)
    try makeWAV().write(to: target)

    let result = try TrackMetadataCopier().copy(
        from: source,
        to: target,
        targetBPM: try BPM(128.5)
    )

    #expect(result.didCopyMetadata)
    #expect(result.copiedChunks.contains("ID3 "))

    guard let copiedTag = riffChunkData(id: "ID3 ", in: try Data(contentsOf: target)) else {
        Issue.record("expected copied ID3 chunk")
        return
    }

    #expect(copiedTag != id3Tag)
    #expect(id3v23TextFrameValue(id: "TIT2", in: copiedTag) == "Source Track")
    #expect(id3v23TextFrameValue(id: "TPE1", in: copiedTag) == "Source Artist")
    #expect(id3v23TextFrameValue(id: "TBPM", in: copiedTag) == "128.5")

    let copiedArtwork = id3v23FramePayload(id: "APIC", in: copiedTag).map {
        Data($0.suffix(artwork.count))
    }
    #expect(copiedArtwork == artwork)
}

@Test func copiesRIFFInfoMetadataAndUpdatesBPM() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("pnt-bpm-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let source = directory.appendingPathComponent("source.wav")
    let target = directory.appendingPathComponent("target.wav")
    let infoList = makeRIFFInfoList([
        ("INAM", "Source Track"),
        ("IART", "Source Artist"),
        ("IBPM", "99")
    ])

    try makeWAV(metadataChunks: [("LIST", infoList)]).write(to: source)
    try makeWAV().write(to: target)

    let result = try TrackMetadataCopier().copy(
        from: source,
        to: target,
        targetBPM: try BPM(127)
    )

    #expect(result.copiedChunks.contains("LIST"))

    guard let copiedList = riffChunkData(id: "LIST", in: try Data(contentsOf: target)) else {
        Issue.record("expected copied LIST chunk")
        return
    }

    #expect(riffInfoValue(id: "INAM", in: copiedList) == "Source Track")
    #expect(riffInfoValue(id: "IART", in: copiedList) == "Source Artist")
    #expect(riffInfoValue(id: "IBPM", in: copiedList) == "127")
}

private func makeAIFFWithID3TBPM(_ bpm: String) -> Data {
    let id3Tag = makeID3v23Tag(frames: [
        makeID3v23TextFrame(id: "TBPM", value: bpm)
    ])
    return makeAIFFWithID3Tag(id3Tag)
}

private func makeAIFFWithID3Tag(_ id3Tag: Data) -> Data {
    let commonChunk = Data([
        0x00, 0x02, // channel count
        0x00, 0x00, 0x00, 0x01, // sample frame count
        0x00, 0x10, // sample size
        0x40, 0x0e, 0xac, 0x44, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 // 44100 Hz
    ])
    let soundChunk = Data([
        0x00, 0x00, 0x00, 0x00, // offset
        0x00, 0x00, 0x00, 0x00, // block size
        0x00, 0x00, 0x00, 0x00 // one silent stereo frame
    ])

    var body = Data()
    body.appendASCII("AIFF")
    body.appendAIFFChunk(id: "COMM", payload: commonChunk)
    body.appendAIFFChunk(id: "SSND", payload: soundChunk)
    body.appendAIFFChunk(id: "ID3 ", payload: id3Tag)

    var file = Data()
    file.appendASCII("FORM")
    file.appendUInt32BE(UInt32(body.count))
    file.append(body)
    return file
}

private func makeWAV(metadataChunks: [(String, Data)] = []) -> Data {
    let fmtChunk = Data([
        0x01, 0x00, // PCM
        0x02, 0x00, // channel count
        0x44, 0xac, 0x00, 0x00, // sample rate: 44100
        0x10, 0xb1, 0x02, 0x00, // byte rate: 176400
        0x04, 0x00, // block align
        0x10, 0x00 // bits per sample
    ])
    let dataChunk = Data([0x00, 0x00, 0x00, 0x00])

    var body = Data()
    body.appendASCII("WAVE")
    body.appendRIFFChunk(id: "fmt ", payload: fmtChunk)
    for (id, payload) in metadataChunks {
        body.appendRIFFChunk(id: id, payload: payload)
    }
    body.appendRIFFChunk(id: "data", payload: dataChunk)

    var file = Data()
    file.appendASCII("RIFF")
    file.appendUInt32LE(UInt32(body.count))
    file.append(body)
    return file
}

private func makeID3v23TextFrame(id: String, value: String) -> Data {
    var payload = Data([0x00])
    payload.append(contentsOf: value.utf8)
    return makeID3v23Frame(id: id, payload: payload)
}

private func makeID3v23ArtworkFrame(mimeType: String, data: Data) -> Data {
    var payload = Data([0x00])
    payload.append(contentsOf: mimeType.utf8)
    payload.append(0x00)
    payload.append(0x03) // front cover
    payload.append(0x00) // empty description
    payload.append(data)
    return makeID3v23Frame(id: "APIC", payload: payload)
}

private func makeID3v23Frame(id: String, payload: Data) -> Data {
    var frame = Data()
    frame.appendASCII(id)
    frame.appendUInt32BE(UInt32(payload.count))
    frame.appendUInt16BE(0)
    frame.append(payload)
    return frame
}

private func makeID3v23Tag(frames: [Data]) -> Data {
    let frameData = frames.reduce(into: Data()) { result, frame in
        result.append(frame)
    }
    var tag = Data()
    tag.appendASCII("ID3")
    tag.append(contentsOf: [0x03, 0x00, 0x00])
    tag.appendSynchsafeUInt32(UInt32(frameData.count))
    tag.append(frameData)
    return tag
}

private func makeRIFFInfoList(_ entries: [(String, String)]) -> Data {
    var list = Data()
    list.appendASCII("INFO")
    for (id, value) in entries {
        var payload = Data(value.utf8)
        payload.append(0)
        list.appendRIFFChunk(id: id, payload: payload)
    }
    return list
}

private func riffChunkData(id: String, in data: Data) -> Data? {
    guard data.count >= 12,
          String(bytes: data[0..<4], encoding: .ascii) == "RIFF",
          String(bytes: data[8..<12], encoding: .ascii) == "WAVE" else {
        return nil
    }

    var offset = 12
    while offset + 8 <= data.count {
        let chunkID = String(bytes: data[offset..<(offset + 4)], encoding: .ascii)
        let chunkSize = Int(data.uint32LE(at: offset + 4))
        let payloadStart = offset + 8
        let payloadEnd = payloadStart + chunkSize
        guard payloadEnd <= data.count else { return nil }
        if chunkID == id {
            return Data(data[payloadStart..<payloadEnd])
        }
        offset = payloadEnd + (chunkSize % 2)
    }

    return nil
}

private func riffInfoValue(id: String, in listData: Data) -> String? {
    guard listData.count >= 4,
          String(bytes: listData[0..<4], encoding: .ascii) == "INFO" else {
        return nil
    }

    var offset = 4
    while offset + 8 <= listData.count {
        let chunkID = String(bytes: listData[offset..<(offset + 4)], encoding: .ascii)
        let chunkSize = Int(listData.uint32LE(at: offset + 4))
        let payloadStart = offset + 8
        let payloadEnd = payloadStart + chunkSize
        guard payloadEnd <= listData.count else { return nil }

        if chunkID == id {
            let payload = listData[payloadStart..<payloadEnd]
            let trimmed = payload.last == 0 ? payload.dropLast() : payload
            return String(bytes: trimmed, encoding: .utf8)
        }

        offset = payloadEnd + (chunkSize % 2)
    }

    return nil
}

private func id3v23TextFrameValue(id: String, in tag: Data) -> String? {
    guard let payload = id3v23FramePayload(id: id, in: tag),
          let encoding = payload.first else {
        return nil
    }

    let valueData = payload.dropFirst()
    switch encoding {
    case 0x00, 0x03:
        return String(bytes: valueData, encoding: .utf8)
    default:
        return nil
    }
}

private func id3v23FramePayload(id: String, in tag: Data) -> Data? {
    guard tag.count >= 10,
          String(bytes: tag[0..<3], encoding: .ascii) == "ID3",
          tag[3] == 0x03 else {
        return nil
    }

    let bodyEnd = min(tag.count, 10 + Int(tag.synchsafeUInt32(at: 6)))
    var offset = 10

    while offset + 10 <= bodyEnd {
        if tag[offset..<(offset + 10)].allSatisfy({ $0 == 0 }) {
            return nil
        }

        let frameID = String(bytes: tag[offset..<(offset + 4)], encoding: .ascii)
        let frameSize = Int(tag.uint32BE(at: offset + 4))
        let payloadStart = offset + 10
        let payloadEnd = payloadStart + frameSize
        guard payloadEnd <= bodyEnd else {
            return nil
        }

        if frameID == id {
            return Data(tag[payloadStart..<payloadEnd])
        }

        offset = payloadEnd
    }

    return nil
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(contentsOf: string.utf8)
    }

    mutating func appendAIFFChunk(id: String, payload: Data) {
        appendASCII(id)
        appendUInt32BE(UInt32(payload.count))
        append(payload)
        if payload.count % 2 == 1 {
            append(0)
        }
    }

    mutating func appendRIFFChunk(id: String, payload: Data) {
        appendASCII(id)
        appendUInt32LE(UInt32(payload.count))
        append(payload)
        if payload.count % 2 == 1 {
            append(0)
        }
    }

    mutating func appendUInt16BE(_ value: UInt16) {
        append(UInt8((value >> 8) & 0xff))
        append(UInt8(value & 0xff))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }

    mutating func appendUInt32BE(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8(value & 0xff))
    }

    mutating func appendSynchsafeUInt32(_ value: UInt32) {
        append(UInt8((value >> 21) & 0x7f))
        append(UInt8((value >> 14) & 0x7f))
        append(UInt8((value >> 7) & 0x7f))
        append(UInt8(value & 0x7f))
    }

    func uint32LE(at offset: Int) -> UInt32 {
        UInt32(self[offset]) |
            (UInt32(self[offset + 1]) << 8) |
            (UInt32(self[offset + 2]) << 16) |
            (UInt32(self[offset + 3]) << 24)
    }

    func uint32BE(at offset: Int) -> UInt32 {
        (UInt32(self[offset]) << 24) |
            (UInt32(self[offset + 1]) << 16) |
            (UInt32(self[offset + 2]) << 8) |
            UInt32(self[offset + 3])
    }

    func synchsafeUInt32(at offset: Int) -> UInt32 {
        (UInt32(self[offset]) << 21) |
            (UInt32(self[offset + 1]) << 14) |
            (UInt32(self[offset + 2]) << 7) |
            UInt32(self[offset + 3])
    }
}
