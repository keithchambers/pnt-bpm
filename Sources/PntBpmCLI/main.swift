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
        let resolvedSource: BPM
        if let provided = options.source {
            resolvedSource = provided
        } else {
            guard let detected = SourceBPMDetector().detect(input: options.input) else {
                throw PntBpmError.undetectableSource(options.input)
            }
            if options.verbose {
                print("detected source BPM \(detected.bpm.description) from \(detected.source)")
            } else {
                print("source BPM \(detected.bpm.description) (auto-detected)")
            }
            resolvedSource = detected.bpm
        }

        let plans = try OutputPlanner.plans(
            input: options.input,
            source: resolvedSource,
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

        let renderer = PitchNTimeRenderer()

        for plan in plans {
            if options.verbose {
                printPlan(plan)
            } else {
                print("\(plan.target.description) BPM -> \(plan.outputURL.path)")
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
                    print("  \(bucket)%")
                }
            }

            print(
                "  wrote \(result.outputURL.path) " +
                "(\(durationString(result.inputDuration)) -> \(durationString(result.outputDuration)))"
            )
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
