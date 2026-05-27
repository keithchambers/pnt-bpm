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

    #expect(options.source.value == 128)
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
