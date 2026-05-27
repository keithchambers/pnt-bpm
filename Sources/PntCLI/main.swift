import Darwin
import Foundation
import PntCliCore

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

private func displayPath(for url: URL) -> String {
    let path = url.path
    let home = NSHomeDirectory()
    if path == home { return "~" }
    if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
    return path
}

private func outputDirDisplay(plans: [OutputPlan], explicitOutDir: URL?) -> String {
    if let explicitOutDir {
        return displayPath(for: explicitOutDir)
    }

    let directories = Set(
        plans.map { $0.outputURL.deletingLastPathComponent().standardizedFileURL.path }
    )
    if directories.count == 1, let directory = directories.first {
        return displayPath(for: URL(fileURLWithPath: directory))
    }
    return "next to each input"
}

private func sourceBPMDisplay(explicit: BPM?, resolved: [(URL, BPM)]) -> String {
    if let explicit { return explicit.description }
    let detected = resolved.map { $0.1 }
    if Set(detected.map(\.value)).count == 1, let first = detected.first {
        return first.description
    }
    return detected.map(\.description).joined(separator: " ")
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
            sourceBPMDisplay: sourceBPMDisplay(explicit: options.source, resolved: resolvedInputs),
            targets: options.targets,
            outDirDisplay: outputDirDisplay(plans: plans, explicitOutDir: options.outDir)
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

    if let failure = reporter.finish() {
        throw failure
    }
}

func run() throws {
    let command = try CLIParser.parse(CommandLine.arguments)

    switch command {
    case .version:
        print(pntCliVersion)
        return

    case .help:
        print(helpText)
        return

    case .render(let options):
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
