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
    let bpm = SourceBPMDetector.scanForBPM(
        in: "Andrew_Meller_Bee_(Original_Mix)__125__Bb_Minor"
    )
    #expect(bpm?.value == 125)
}

@Test func ignoresBeatportTrackIdInBPMSlot() {
    // Older Beatport AIFFs used a 7–8 digit track ID in the same slot.
    let bpm = SourceBPMDetector.scanForBPM(
        in: "Emi_Galvan_Samsara_(Original_Mix)__17628366__E_Major"
    )
    #expect(bpm == nil)
}

@Test func detectsMvsepTrailingBPM() {
    #expect(SourceBPMDetector.scanForBPM(in: "technasia-i-am-somebody-original-mix-125")?.value == 125)
    #expect(SourceBPMDetector.scanForBPM(in: "tuccillo-unblock-original-mix-120-g-mi")?.value == 120)
    #expect(SourceBPMDetector.scanForBPM(in: "andrew-meller-bee-original-mix-125-bb-minor")?.value == 125)
}

@Test func rejectsImplausibleTrailingNumber() {
    // mvsep duplicate-suffix counters like "-1", "-2" must not be read as BPM.
    #expect(SourceBPMDetector.scanForBPM(in: "andain-beautiful-things-original-mix-1") == nil)
    // Track-number prefixes shouldn't get picked up as BPM either.
    #expect(SourceBPMDetector.scanForBPM(in: "01-hermanez-gold-coast-original") == nil)
}

@Test func walksUpParentDirectoriesForBPM() {
    // Synthesize the mvsep nested layout: <track>/<run>/vocals.wav
    let url = URL(fileURLWithPath: "/tmp/mvsep-test/technasia-i-am-somebody-original-mix-125/2025-01-16_all_in_ensemble/vocals.wav")
    let detected = SourceBPMDetector().detect(input: url)
    #expect(detected?.bpm.value == 125)
    #expect(detected?.source.hasPrefix("parent dir:") == true)
}
