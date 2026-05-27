import Darwin
import Foundation
import PntBpmCore

func durationString(_ seconds: Double) -> String {
    let minutes = Int(seconds) / 60
    let remainder = seconds - Double(minutes * 60)
    return String(format: "%d:%06.3f", minutes, remainder)
}

func printPlan(_ plan: OutputPlan) {
    print(
        "\(plan.source.description) -> \(plan.target.description) BPM  " +
        "time=\(String(format: "%.6f", plan.ratios.seratoTime))  " +
        "duration=\(String(format: "%.6f", plan.ratios.outputDurationRatio))x  " +
        "\(plan.outputURL.path)"
    )
}

private final class LockedPrinter: @unchecked Sendable {
    private let lock = NSLock()

    func line(_ message: String) {
        lock.withLock {
            print(message)
        }
    }

    func plan(_ plan: OutputPlan) {
        lock.withLock {
            printPlan(plan)
        }
    }
}

func resolveSources(for inputs: [URL], explicit: BPM?, verbose: Bool) throws -> [(URL, BPM)] {
    if let explicit {
        return inputs.map { ($0, explicit) }
    }
    let detector = SourceBPMDetector()
    return try inputs.map { input in
        guard let detected = detector.detect(input: input) else {
            throw PntBpmError.undetectableSource(input)
        }
        let label = inputs.count > 1 ? " for \(input.lastPathComponent)" : ""
        if verbose {
            print("detected source BPM \(detected.bpm.description) from \(detected.source)\(label)")
        } else {
            print("source BPM \(detected.bpm.description) (auto-detected)\(label)")
        }
        return (input, detected.bpm)
    }
}

private func validateOutputsAvailable(_ plans: [OutputPlan], overwrite: Bool) throws {
    guard !overwrite else { return }

    for plan in plans where FileManager.default.fileExists(atPath: plan.outputURL.path) {
        throw PntBpmError.outputExists(plan.outputURL)
    }
}

@discardableResult
private func renderPlan(
    _ plan: OutputPlan,
    options: RenderOptions,
    renderer: PitchNTimeRenderer,
    printer: LockedPrinter,
    progressLabel: String?
) throws -> RenderResult {
    if options.verbose {
        printer.plan(plan)
    } else {
        printer.line("\(plan.target.description) BPM -> \(plan.outputURL.path)")
    }

    var lastProgressBucket = -1
    let result = try renderer.render(
        plan: plan,
        overwrite: options.overwrite,
        gain: options.gain,
        tailMilliseconds: options.tailMilliseconds
    ) { progress in
        guard options.verbose else { return }
        let bucket = Int((progress.fraction * 100).rounded(.down))
        if bucket >= lastProgressBucket + 10 || bucket == 100 {
            lastProgressBucket = bucket
            if let progressLabel {
                printer.line("  \(progressLabel): \(bucket)%")
            } else {
                printer.line("  \(bucket)%")
            }
        }
    }

    printer.line(
        "  wrote \(result.outputURL.path) " +
        "(\(durationString(result.inputDuration)) -> \(durationString(result.outputDuration)))"
    )
    return result
}

func run() throws {
    switch try CLIParser.parse(CommandLine.arguments) {
    case .help:
        print(helpText)

    case .version:
        print(pntBpmVersion)

    case .doctor(let verbose):
        let report = try PitchNTimeAudioUnit.doctor()
        print("Serato Pitch n Time LE: OK")
        print("Name: \(report.name)")
        print("Manufacturer: \(report.manufacturer)")
        if verbose {
            print("Parameters:")
            for parameter in report.parameters {
                print("  \(parameter)")
            }
        }

    case .render(let options):
        let resolvedInputs = try resolveSources(
            for: options.inputs,
            explicit: options.source,
            verbose: options.verbose
        )

        let plans = try OutputPlanner.plans(
            inputs: resolvedInputs,
            targets: options.targets,
            outDir: options.outDir,
            format: options.format,
            nameTemplate: options.nameTemplate
        )

        if options.dryRun {
            for plan in plans {
                printPlan(plan)
            }
            return
        }

        try validateOutputsAvailable(plans, overwrite: options.overwrite)
        let printer = LockedPrinter()
        let jobs = RenderOptions.defaultJobs

        if jobs == 1 {
            let renderer = PitchNTimeRenderer()
            for plan in plans {
                try renderPlan(
                    plan,
                    options: options,
                    renderer: renderer,
                    printer: printer,
                    progressLabel: nil
                )
            }
        } else {
            _ = try RenderBatchRunner.render(
                plans: plans,
                jobs: jobs
            ) { plan in
                try renderPlan(
                    plan,
                    options: options,
                    renderer: PitchNTimeRenderer(),
                    printer: printer,
                    progressLabel: plan.outputURL.lastPathComponent
                )
            }
        }
    }
}

do {
    try run()
} catch let error as PntBpmError {
    fputs("pnt-bpm: \(error.description)\n", stderr)
    exit(1)
} catch {
    fputs("pnt-bpm: \(error.localizedDescription)\n", stderr)
    exit(1)
}
