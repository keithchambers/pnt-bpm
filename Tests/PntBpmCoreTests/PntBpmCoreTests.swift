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
        "pnt-bpm", "song.aiff", "--target", "125"
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

private func makeAIFFWithID3TBPM(_ bpm: String) -> Data {
    let id3Tag = makeID3v23TBPMTag(bpm)
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

private func makeID3v23TBPMTag(_ bpm: String) -> Data {
    var text = Data([0x00])
    text.append(contentsOf: bpm.utf8)

    var frame = Data()
    frame.appendASCII("TBPM")
    frame.appendUInt32BE(UInt32(text.count))
    frame.appendUInt16BE(0)
    frame.append(text)

    var tag = Data()
    tag.appendASCII("ID3")
    tag.append(contentsOf: [0x03, 0x00, 0x00])
    tag.appendSynchsafeUInt32(UInt32(frame.count))
    tag.append(frame)
    return tag
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

    mutating func appendUInt16BE(_ value: UInt16) {
        append(UInt8((value >> 8) & 0xff))
        append(UInt8(value & 0xff))
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
}
