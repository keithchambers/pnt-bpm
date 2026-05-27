import Foundation

public struct OutputPlan: Equatable, Sendable {
    public let input: URL
    public let outputURL: URL
    public let source: BPM
    public let target: BPM
    public let ratios: TempoRatios

    public init(input: URL, outputURL: URL, source: BPM, target: BPM) {
        self.input = input
        self.outputURL = outputURL
        self.source = source
        self.target = target
        self.ratios = TempoRatios(source: source, target: target)
    }
}

public struct OutputPlanner {
    public static func plans(
        input: URL,
        source: BPM,
        targets: [BPM],
        outDir: URL?
    ) throws -> [OutputPlan] {
        try plans(
            inputs: [(input, source)],
            targets: targets,
            outDir: outDir
        )
    }

    public static func plans(
        inputs: [URL],
        source: BPM,
        targets: [BPM],
        outDir: URL?
    ) throws -> [OutputPlan] {
        try plans(
            inputs: inputs.map { ($0, source) },
            targets: targets,
            outDir: outDir
        )
    }

    public static func plans(
        inputs: [(URL, BPM)],
        targets: [BPM],
        outDir: URL?
    ) throws -> [OutputPlan] {
        guard !inputs.isEmpty else {
            throw PntCliError.missingInput
        }

        var plans: [OutputPlan] = []
        var seenOutputs: Set<String> = []

        for (input, source) in inputs {
            let directory = outDir ?? input.deletingLastPathComponent()
            let title = input.deletingPathExtension().lastPathComponent
            let ext = input.pathExtension

            for target in targets {
                let filename = "\(title)_\(target.description)bpm.\(ext)"
                let outputURL = directory.appendingPathComponent(filename)
                if !seenOutputs.insert(outputURL.standardizedFileURL.path).inserted {
                    throw PntCliError.outputCollision(outputURL)
                }
                plans.append(
                    OutputPlan(
                        input: input,
                        outputURL: outputURL,
                        source: source,
                        target: target
                    )
                )
            }
        }

        return plans
    }
}
