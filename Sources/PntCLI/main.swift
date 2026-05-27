import Darwin
import Foundation
import PntCliCore

private let pntMissingWarning = """

⚠  Serato Pitch n' Time LE is not installed (or not loadable).
   pnt-cli needs the Pitch n' Time LE Audio Unit to render audio.
   Install Pitch n' Time LE from Serato, then run `pnt-cli --help` again to confirm.
"""

func resolveSources(for inputs: [URL], explicit: BPM?) throws -> [(URL, BPM)] {
    if let explicit {
        return inputs.map { ($0, explicit) }
    }
    let detector = SourceBPMDetector()
    return try inputs.map { input in
        guard let detected = detector.detect(input: input) else {
            throw PntCliError.undetectableSource(input)
        }
        return (input, detected.bpm)
    }
}

private func validateOutputsAvailable(_ plans: [OutputPlan], overwrite: Bool) throws {
    guard !overwrite else { return }
    for plan in plans where FileManager.default.fileExists(atPath: plan.outputURL.path) {
        throw PntCliError.outputExists(plan.outputURL)
    }
}

private func displayPath(for url: URL?) -> String {
    let path = (url ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).path
    let home = NSHomeDirectory()
    if path == home { return "~" }
    if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
    return path
}

private func sourceBPMDisplay(_ source: BPM?) -> String {
    if let source { return source.description }
    return "auto-detected"
}

private func runRender(_ options: RenderOptions) throws {
    let resolvedInputs = try resolveSources(for: options.inputs, explicit: options.source)

    let plans = try OutputPlanner.plans(
        inputs: resolvedInputs,
        targets: options.targets,
        outDir: options.outDir
    )

    try validateOutputsAvailable(plans, overwrite: options.overwrite)

    let reporter = Reporter()
    reporter.printPlan(
        Reporter.Plan(
            tracks: options.inputs.count,
            sourceBPMDisplay: sourceBPMDisplay(options.source),
            targets: options.targets,
            outDirDisplay: displayPath(for: options.outDir)
        )
    )

    reporter.start(totalRenders: plans.count)
    let jobs = RenderOptions.defaultJobs

    RenderBatchRunner.forEach(plans: plans, jobs: jobs) { plan in
        do {
            let renderer = PitchNTimeRenderer()
            _ = try renderer.render(plan: plan, overwrite: options.overwrite)
            reporter.recordCompleted()
        } catch {
            reporter.recordFailed(error)
        }
    }

    reporter.finish()
}

func run() throws {
    let command = try CLIParser.parse(CommandLine.arguments)

    switch command {
    case .version:
        print(pntCliVersion)
        return

    case .help:
        print(helpText)
        if !PitchNTimeAudioUnit.isAvailable() {
            fputs(pntMissingWarning + "\n", stderr)
            exit(1)
        }
        return

    case .render(let options):
        guard PitchNTimeAudioUnit.isAvailable() else {
            print(helpText)
            fputs(pntMissingWarning + "\n", stderr)
            exit(1)
        }
        try runRender(options)
    }
}

do {
    try run()
} catch let error as PntCliError {
    fputs("pnt-cli: \(error.description)\n", stderr)
    exit(1)
} catch {
    fputs("pnt-cli: \(error.localizedDescription)\n", stderr)
    exit(1)
}
