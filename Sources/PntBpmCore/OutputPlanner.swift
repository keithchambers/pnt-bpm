import Foundation

public struct OutputPlan: Equatable {
    public let input: URL
    public let outputURL: URL
    public let source: BPM
    public let target: BPM
    public let ratios: TempoRatios
    public let format: String

    public init(input: URL, outputURL: URL, source: BPM, target: BPM, format: String) {
        self.input = input
        self.outputURL = outputURL
        self.source = source
        self.target = target
        self.ratios = TempoRatios(source: source, target: target)
        self.format = format
    }
}

public struct OutputPlanner {
    public static func plans(
        input: URL,
        source: BPM,
        targets: [BPM],
        outDir: URL?,
        format: String,
        nameTemplate: String
    ) throws -> [OutputPlan] {
        try plans(
            inputs: [(input, source)],
            targets: targets,
            outDir: outDir,
            format: format,
            nameTemplate: nameTemplate
        )
    }

    public static func plans(
        inputs: [URL],
        source: BPM,
        targets: [BPM],
        outDir: URL?,
        format: String,
        nameTemplate: String
    ) throws -> [OutputPlan] {
        try plans(
            inputs: inputs.map { ($0, source) },
            targets: targets,
            outDir: outDir,
            format: format,
            nameTemplate: nameTemplate
        )
    }

    public static func plans(
        inputs: [(URL, BPM)],
        targets: [BPM],
        outDir: URL?,
        format: String,
        nameTemplate: String
    ) throws -> [OutputPlan] {
        guard !inputs.isEmpty else {
            throw PntBpmError.missingInput
        }

        let normalizedFormat = format.lowercased()
        guard normalizedFormat == "wav" else {
            throw PntBpmError.unsupportedFormat(format)
        }

        var plans: [OutputPlan] = []
        var seenOutputs: Set<String> = []

        for (input, source) in inputs {
            let directory = outDir ?? input.deletingLastPathComponent()
            let title = input.deletingPathExtension().lastPathComponent

            for target in targets {
                let filename = renderName(
                    template: nameTemplate,
                    title: title,
                    bpm: target.description,
                    ext: normalizedFormat
                )
                let outputURL = directory.appendingPathComponent(filename)
                if !seenOutputs.insert(outputURL.standardizedFileURL.path).inserted {
                    throw PntBpmError.outputCollision(outputURL)
                }
                plans.append(
                    OutputPlan(
                        input: input,
                        outputURL: outputURL,
                        source: source,
                        target: target,
                        format: normalizedFormat
                    )
                )
            }
        }

        return plans
    }

    public static func renderName(template: String, title: String, bpm: String, ext: String) -> String {
        template
            .replacingOccurrences(of: "{title}", with: title)
            .replacingOccurrences(of: "{bpm}", with: bpm)
            .replacingOccurrences(of: "{ext}", with: ext)
    }
}
