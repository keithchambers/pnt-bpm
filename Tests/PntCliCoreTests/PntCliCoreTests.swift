import AVFoundation
import Foundation
import Testing
@testable import PntCliCore

@Test func parsesCommaSeparatedTargets() throws {
    let targets = try parseBPMList(["125,122,120"])
    #expect(targets.map(\.value) == [125, 122, 120])
}

@Test func parsesRepeatedTargets() throws {
    let command = try CLIParser.parse([
        "pnt-cli",
        "song.wav",
        "--source",
        "128",
        "--target",
        "125",
        "-t",
        "122,120"
    ])

    guard case .render(let options) = command else {
        Issue.record("expected render command")
        return
    }

    #expect(options.source?.value == 128)
    #expect(options.targets.map(\.value) == [125, 122, 120])
}

@Test func parsesOverwriteAliases() throws {
    for flag in ["-o", "--overwrite"] {
        let command = try CLIParser.parse([
            "pnt-cli",
            "song.wav",
            "--source",
            "128",
            "--target",
            "125",
            flag
        ])

        guard case .render(let options) = command else {
            Issue.record("expected render command")
            return
        }

        #expect(options.overwrite)
    }
}

@Test func emptyArgumentsShowHelp() throws {
    #expect(try CLIParser.parse(["pnt-cli"]) == .help)
}

@Test func parsesShortVersionFlag() throws {
    #expect(try CLIParser.parse(["pnt-cli", "-v"]) == .version)
}

@Test func computesSeratoTimeAndDurationRatios() throws {
    let source = try BPM(120)
    let target = try BPM(128)
    let ratios = TempoRatios(source: source, target: target)

    #expect(abs(ratios.seratoTime - 1.0666666667) < 0.0000001)
    #expect(abs(ratios.outputDurationRatio - 0.9375) < 0.0000001)
}

@Test func outputFrameCountUsesExactDecimalBPMMath() throws {
    let ratios = TempoRatios(source: try BPM("50.1"), target: try BPM("75.6"))

    #expect(Int64((Double(44_100) * (50.1 / 75.6)).rounded(.up)) == 29_226)
    #expect(try ratios.outputFrameCount(inputFrames: 44_100) == 29_225)
}

@Test func outputExtensionMatchesInput() throws {
    let input = URL(fileURLWithPath: "/tmp/song.aiff")
    let plans = try OutputPlanner.plans(
        input: input,
        source: try BPM(120),
        targets: [try BPM(125), try BPM(128)],
        outDir: nil
    )

    #expect(plans.map { $0.outputURL.path } == [
        "/tmp/song_125bpm.aiff",
        "/tmp/song_128bpm.aiff"
    ])
}

@Test func outputNameOmitsTrailingDotWhenInputHasNoExtension() throws {
    let plans = try OutputPlanner.plans(
        input: URL(fileURLWithPath: "/tmp/song"),
        source: try BPM(120),
        targets: [try BPM(125)],
        outDir: nil
    )

    #expect(plans.map { $0.outputURL.path } == ["/tmp/song_125bpm"])
}

@Test func rejectsMissingTargets() {
    #expect(throws: PntCliError.missingTargets) {
        _ = try CLIParser.parse(["pnt-cli", "song.wav", "--source", "120"])
    }
}

@Test func rejectsMP3Inputs() {
    #expect(throws: PntCliError.unsupportedInputFormat(URL(fileURLWithPath: "/tmp/song.mp3"))) {
        _ = try CLIParser.parse([
            "pnt-cli",
            "/tmp/song.mp3",
            "--source",
            "120",
            "--target",
            "125"
        ])
    }

    #expect(throws: PntCliError.unsupportedInputFormat(URL(fileURLWithPath: "/tmp/song.MP3"))) {
        _ = try CLIParser.parse([
            "pnt-cli",
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
        "pnt-cli",
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
        "pnt-cli",
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

@Test func defaultJobsIsPositive() {
    #expect(RenderOptions.defaultJobs >= 1)
}

@Test func rejectsJobsOverride() {
    #expect(throws: PntCliError.invalidOption("--jobs")) {
        _ = try CLIParser.parse([
            "pnt-cli",
            "song.wav",
            "--source",
            "128",
            "--target",
            "125",
            "--jobs",
            "4"
        ])
    }
}

@Test func rejectsCopyMetadataFlagBecauseMetadataCopyIsAutomatic() {
    #expect(throws: PntCliError.invalidOption("--copy-metadata")) {
        _ = try CLIParser.parse([
            "pnt-cli",
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

@Test func renderBatchRunnerRunsBoundedJobsConcurrentlyAndKeepsResultOrder() throws {
    let plans = try (0..<4).map(makeTestPlan)
    let state = ParallelRunnerTestState()
    let started = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    let finished = DispatchSemaphore(value: 0)

    DispatchQueue.global(qos: .userInitiated).async {
        do {
            let results = try RenderBatchRunner.render(plans: plans, jobs: 2) { plan in
                state.enter()
                started.signal()
                release.wait()
                state.leave()

                let value = AVAudioFramePosition(Int64(plan.target.value))
                return RenderResult(
                    outputURL: plan.outputURL,
                    inputFrames: value,
                    renderedFrames: value,
                    sampleRate: 1,
                    seratoTime: plan.ratios.seratoTime,
                    durationRatio: plan.ratios.outputDurationRatio
                )
            }
            state.setValues(results.map(\.inputFrames))
        } catch {
            state.setError(error)
        }
        finished.signal()
    }

    #expect(started.wait(timeout: .now() + .seconds(2)) == .success)
    #expect(started.wait(timeout: .now() + .seconds(2)) == .success)
    #expect(state.maxActiveValue == 2)

    for _ in plans {
        release.signal()
    }

    #expect(finished.wait(timeout: .now() + .seconds(2)) == .success)
    #expect(state.errorDescription == nil)
    #expect(state.values == [120, 121, 122, 123])
}

@Test func reporterExposesFirstRecordedFailure() {
    let reporter = Reporter(forceTTY: false)
    let expected = PntCliError.renderFailed("boom")

    reporter.start(totalRenders: 2)
    reporter.recordStarted()
    reporter.recordFailed(expected)
    reporter.recordStarted()
    reporter.recordCompleted()
    let failure = reporter.finish()

    #expect((failure as? PntCliError) == expected)
}

@Test func reporterLiveStatusShowsActiveRenders() {
    let line = Reporter.liveStatusLine(
        spinner: "⠋",
        done: 0,
        total: 11,
        active: 11,
        elapsed: 2,
        remaining: nil
    )

    #expect(line == "⠋  Rendering 0 of 11 done · 11 active · 0:02 elapsed")
}

@Test func reporterLiveBlockClearSequenceRewindsTwoPrintedLines() {
    #expect(Reporter.clearLiveBlockSequence == "\u{1B}[1A\u{1B}[2K\r\u{1B}[1A\u{1B}[2K\r")
}

@Test func audioUnitLoadErrorsExplainRecovery() {
    let notFound = PntCliError.audioUnitNotFound.description
    #expect(notFound.contains("processing audio"))
    #expect(notFound.contains("Install"))
    #expect(notFound.contains("authorized"))

    let instantiateFailed = PntCliError.audioUnitInstantiateFailed("blocked").description
    #expect(instantiateFailed.contains("processing audio"))
    #expect(instantiateFailed.contains("installed"))
    #expect(instantiateFailed.contains("authorized"))

    let missingParameter = PntCliError.missingAudioUnitParameter("Time").description
    #expect(missingParameter.contains("Reinstall or update"))
    #expect(missingParameter.contains("Pitch n Time LE 3.1.1"))
}

@Test func multiInputPlansFanOutOverInputsAndTargets() throws {
    let plans = try OutputPlanner.plans(
        inputs: [
            URL(fileURLWithPath: "/tmp/a.wav"),
            URL(fileURLWithPath: "/tmp/b.aiff")
        ],
        source: try BPM(120),
        targets: [try BPM(125), try BPM(128)],
        outDir: nil
    )

    #expect(plans.map { $0.outputURL.path } == [
        "/tmp/a_125bpm.wav",
        "/tmp/a_128bpm.wav",
        "/tmp/b_125bpm.aiff",
        "/tmp/b_128bpm.aiff"
    ])
}

@Test func multiInputPlansSupportPerInputSource() throws {
    let plans = try OutputPlanner.plans(
        inputs: [
            (URL(fileURLWithPath: "/tmp/a.wav"), try BPM(120)),
            (URL(fileURLWithPath: "/tmp/b.aiff"), try BPM(128))
        ],
        targets: [try BPM(125)],
        outDir: nil
    )

    #expect(plans.map(\.source.value) == [120, 128])
    #expect(plans.map { $0.outputURL.path } == [
        "/tmp/a_125bpm.wav",
        "/tmp/b_125bpm.aiff"
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
        outDir: URL(fileURLWithPath: "/renders")
    )

    #expect(plans.map { $0.outputURL.path } == [
        "/renders/a_125bpm.wav",
        "/renders/b_125bpm.wav"
    ])
}

@Test func rejectsCollidingOutputsAcrossInputs() {
    #expect(throws: PntCliError.outputCollision(URL(fileURLWithPath: "/renders/song_125bpm.wav"))) {
        _ = try OutputPlanner.plans(
            inputs: [
                URL(fileURLWithPath: "/a/song.wav"),
                URL(fileURLWithPath: "/b/song.wav")
            ],
            source: try BPM(120),
            targets: [try BPM(125)],
            outDir: URL(fileURLWithPath: "/renders")
        )
    }
}

@Test func rejectsEmptyInputs() {
    #expect(throws: PntCliError.missingInput) {
        _ = try OutputPlanner.plans(
            inputs: [],
            source: try BPM(120),
            targets: [try BPM(125)],
            outDir: nil
        )
    }
}

@Test func sourceIsOptionalWhenAutoDetectIntended() throws {
    let command = try CLIParser.parse([
        "pnt-cli",
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
        .appendingPathComponent("pnt-cli-tests-\(UUID().uuidString)", isDirectory: true)
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
        .appendingPathComponent("pnt-cli-tests-\(UUID().uuidString)", isDirectory: true)
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
    // WAV targets should get the lowercase RIFF-canonical "id3 " chunk id.
    #expect(result.copiedChunks.contains("id3 "))
    #expect(!result.copiedChunks.contains("ID3 "))

    guard let copiedTag = riffChunkData(id: "id3 ", in: try Data(contentsOf: target)) else {
        Issue.record("expected copied id3 chunk")
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
        .appendingPathComponent("pnt-cli-tests-\(UUID().uuidString)", isDirectory: true)
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

@Test func doesNotDuplicateRepeatedMetadataChunksFromSource() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("pnt-cli-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let source = directory.appendingPathComponent("source.wav")
    let target = directory.appendingPathComponent("target.wav")
    let firstInfo = makeRIFFInfoList([("INAM", "First")])
    let secondInfo = makeRIFFInfoList([("INAM", "Second")])

    try makeWAV(metadataChunks: [
        ("LIST", firstInfo),
        ("LIST", secondInfo)
    ]).write(to: source)
    try makeWAV().write(to: target)

    let result = try TrackMetadataCopier().copy(
        from: source,
        to: target,
        targetBPM: try BPM(125)
    )

    let copiedListCount = result.copiedChunks.filter { $0 == "LIST" }.count
    #expect(copiedListCount == 2)
    #expect(countRIFFChunks(id: "LIST", in: try Data(contentsOf: target)) == 2)
}

@Test func leavesUnsynchronisedID3TagsUntouched() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("pnt-cli-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let source = directory.appendingPathComponent("source.aiff")
    let target = directory.appendingPathComponent("target.wav")
    var id3Tag = makeID3v23Tag(frames: [
        makeID3v23TextFrame(id: "TBPM", value: "99")
    ])
    id3Tag[5] |= 0x80 // mark tag-level unsynchronisation

    try makeAIFFWithID3Tag(id3Tag).write(to: source)
    try makeWAV().write(to: target)

    _ = try TrackMetadataCopier().copy(
        from: source,
        to: target,
        targetBPM: try BPM(128)
    )

    guard let copiedTag = riffChunkData(id: "id3 ", in: try Data(contentsOf: target)) else {
        Issue.record("expected copied id3 chunk")
        return
    }

    // The tag should round-trip unchanged because we don't risk rewriting it
    // when unsynchronisation is in play.
    #expect(copiedTag == id3Tag)
    #expect(id3v23TextFrameValue(id: "TBPM", in: copiedTag) == "99")
}

@Test func leavesTBPMFrameAloneWhenFrameFlagsAreSet() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("pnt-cli-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let source = directory.appendingPathComponent("source.aiff")
    let target = directory.appendingPathComponent("target.wav")

    var tbpmFrame = makeID3v23TextFrame(id: "TBPM", value: "99")
    tbpmFrame[9] = 0x80 // simulate a frame-level "compression" flag
    let id3Tag = makeID3v23Tag(frames: [
        makeID3v23TextFrame(id: "TIT2", value: "Source Track"),
        tbpmFrame
    ])

    try makeAIFFWithID3Tag(id3Tag).write(to: source)
    try makeWAV().write(to: target)

    _ = try TrackMetadataCopier().copy(
        from: source,
        to: target,
        targetBPM: try BPM(128)
    )

    guard let copiedTag = riffChunkData(id: "id3 ", in: try Data(contentsOf: target)) else {
        Issue.record("expected copied id3 chunk")
        return
    }

    // Other frames still come through, but the flagged TBPM stays exactly as
    // it was rather than being silently invalidated by a plain-text rewrite.
    #expect(id3v23TextFrameValue(id: "TIT2", in: copiedTag) == "Source Track")
    #expect(id3v23FramePayload(id: "TBPM", in: copiedTag) == Data([0x00] + Array("99".utf8)))
}

@Test func writesUppercaseID3ChunkToAIFFTarget() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("pnt-cli-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let source = directory.appendingPathComponent("source.aiff")
    let target = directory.appendingPathComponent("target.aiff")
    let id3Tag = makeID3v23Tag(frames: [
        makeID3v23TextFrame(id: "TBPM", value: "99")
    ])

    try makeAIFFWithID3Tag(id3Tag).write(to: source)
    try makeAIFFWithID3Tag(makeID3v23Tag(frames: [])).write(to: target)

    let result = try TrackMetadataCopier().copy(
        from: source,
        to: target,
        targetBPM: try BPM(120)
    )

    // AIFF keeps the uppercase "ID3 " chunk id.
    #expect(result.copiedChunks.contains("ID3 "))
    #expect(!result.copiedChunks.contains("id3 "))
    #expect(aiffChunkData(id: "ID3 ", in: try Data(contentsOf: target)) != nil)
}

@Test func skipsAIFFOnlyChunksWhenWritingToWAVTarget() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("pnt-cli-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let source = directory.appendingPathComponent("source.aiff")
    let target = directory.appendingPathComponent("target.wav")

    // AIFF-only chunks like NAME / AUTH / ANNO have no meaning in RIFF/WAVE
    // and shouldn't bleed into a WAV target as non-standard chunks.
    let aiffWithAIFFChunks = makeAIFFWithAIFFOnlyChunks(
        nameValue: "Source Track",
        authorValue: "Source Artist"
    )
    try aiffWithAIFFChunks.write(to: source)
    try makeWAV().write(to: target)

    let result = try TrackMetadataCopier().copy(
        from: source,
        to: target,
        targetBPM: try BPM(125)
    )

    #expect(!result.copiedChunks.contains("NAME"))
    #expect(!result.copiedChunks.contains("AUTH"))

    let bytes = try Data(contentsOf: target)
    #expect(riffChunkData(id: "NAME", in: bytes) == nil)
    #expect(riffChunkData(id: "AUTH", in: bytes) == nil)
}

private final class ParallelRunnerTestState: @unchecked Sendable {
    private let lock = NSLock()
    private var active = 0
    private var maxActive = 0
    private var storedValues: [AVAudioFramePosition]?
    private var storedError: Error?

    var maxActiveValue: Int {
        lock.withLock { maxActive }
    }

    var values: [AVAudioFramePosition]? {
        lock.withLock { storedValues }
    }

    var errorDescription: String? {
        lock.withLock { storedError.map(String.init(describing:)) }
    }

    func enter() {
        lock.withLock {
            active += 1
            maxActive = max(maxActive, active)
        }
    }

    func leave() {
        lock.withLock {
            active -= 1
        }
    }

    func setValues(_ values: [AVAudioFramePosition]) {
        lock.withLock {
            storedValues = values
        }
    }

    func setError(_ error: Error) {
        lock.withLock {
            storedError = error
        }
    }
}

private func makeTestPlan(index: Int) throws -> OutputPlan {
    OutputPlan(
        input: URL(fileURLWithPath: "/tmp/input-\(index).wav"),
        outputURL: URL(fileURLWithPath: "/tmp/output-\(index).wav"),
        source: try BPM(120),
        target: try BPM(120 + Double(index))
    )
}

private func makeAIFFWithAIFFOnlyChunks(nameValue: String, authorValue: String) -> Data {
    let commonChunk = Data([
        0x00, 0x02,
        0x00, 0x00, 0x00, 0x01,
        0x00, 0x10,
        0x40, 0x0e, 0xac, 0x44, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ])
    let soundChunk = Data([
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00
    ])

    var body = Data()
    body.appendASCII("AIFF")
    body.appendAIFFChunk(id: "COMM", payload: commonChunk)
    body.appendAIFFChunk(id: "SSND", payload: soundChunk)
    body.appendAIFFChunk(id: "NAME", payload: Data(nameValue.utf8))
    body.appendAIFFChunk(id: "AUTH", payload: Data(authorValue.utf8))

    var file = Data()
    file.appendASCII("FORM")
    file.appendUInt32BE(UInt32(body.count))
    file.append(body)
    return file
}

private func aiffChunkData(id: String, in data: Data) -> Data? {
    guard data.count >= 12,
          String(bytes: data[0..<4], encoding: .ascii) == "FORM",
          String(bytes: data[8..<12], encoding: .ascii) == "AIFF" else {
        return nil
    }

    var offset = 12
    while offset + 8 <= data.count {
        let chunkID = String(bytes: data[offset..<(offset + 4)], encoding: .ascii)
        let chunkSize = Int(data.uint32BE(at: offset + 4))
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

private func countRIFFChunks(id: String, in data: Data) -> Int {
    guard data.count >= 12,
          String(bytes: data[0..<4], encoding: .ascii) == "RIFF",
          String(bytes: data[8..<12], encoding: .ascii) == "WAVE" else {
        return 0
    }

    var offset = 12
    var count = 0
    while offset + 8 <= data.count {
        let chunkID = String(bytes: data[offset..<(offset + 4)], encoding: .ascii)
        let chunkSize = Int(data.uint32LE(at: offset + 4))
        let payloadStart = offset + 8
        let payloadEnd = payloadStart + chunkSize
        guard payloadEnd <= data.count else { return count }
        if chunkID == id { count += 1 }
        offset = payloadEnd + (chunkSize % 2)
    }
    return count
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
