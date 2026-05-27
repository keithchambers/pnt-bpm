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
        let normalizedFormat = format.lowercased()
        guard normalizedFormat == "wav" else {
            throw PntBpmError.unsupportedFormat(format)
        }

        let directory = outDir ?? input.deletingLastPathComponent()
        let title = input.deletingPathExtension().lastPathComponent

        return targets.map { target in
            let filename = renderName(
                template: nameTemplate,
                title: title,
                bpm: target.description,
                ext: normalizedFormat
            )
            return OutputPlan(
                input: input,
                outputURL: directory.appendingPathComponent(filename),
                source: source,
                target: target,
                format: normalizedFormat
            )
        }
    }

    public static func renderName(template: String, title: String, bpm: String, ext: String) -> String {
        template
            .replacingOccurrences(of: "{title}", with: title)
            .replacingOccurrences(of: "{bpm}", with: bpm)
            .replacingOccurrences(of: "{ext}", with: ext)
    }
}
