import Foundation

public enum Command: Equatable, Sendable {
    case render(RenderOptions)
    case help
    case version
}

public struct RenderOptions: Equatable, Sendable {
    public static var defaultJobs: Int {
        max(1, ProcessInfo.processInfo.activeProcessorCount)
    }

    public var inputs: [URL]
    /// Source BPM applied to every input. nil means "auto-detect per input".
    public var source: BPM?
    public var targets: [BPM]
    public var outDir: URL?
    public var overwrite: Bool

    public var input: URL {
        inputs[0]
    }

    public init(
        inputs: [URL],
        source: BPM?,
        targets: [BPM],
        outDir: URL? = nil,
        overwrite: Bool = false
    ) {
        self.inputs = inputs
        self.source = source
        self.targets = targets
        self.outDir = outDir
        self.overwrite = overwrite
    }

    public init(
        input: URL,
        source: BPM?,
        targets: [BPM],
        outDir: URL? = nil,
        overwrite: Bool = false
    ) {
        self.init(
            inputs: [input],
            source: source,
            targets: targets,
            outDir: outDir,
            overwrite: overwrite
        )
    }
}

public struct CLIParser {
    public static func parse(_ arguments: [String]) throws -> Command {
        var args = Array(arguments.dropFirst())
        if args.isEmpty {
            return .help
        }

        var inputPaths: [String] = []
        var sourceRaw: String?
        var targetRaw: [String] = []
        var outDirPath: String?
        var overwrite = false

        func popValue(after option: String) throws -> String {
            guard !args.isEmpty else {
                throw PntCliError.usage("\(option) requires a value")
            }
            return args.removeFirst()
        }

        while !args.isEmpty {
            let arg = args.removeFirst()
            switch arg {
            case "-h", "--help":
                return .help
            case "-v", "--version":
                return .version
            case "-i", "--input":
                inputPaths.append(try popValue(after: arg))
            case "-s", "--source":
                sourceRaw = try popValue(after: arg)
            case "-t", "--target":
                targetRaw.append(try popValue(after: arg))
            case "-d", "--out-dir":
                outDirPath = try popValue(after: arg)
            case "--overwrite":
                overwrite = true
            default:
                if arg.hasPrefix("-") {
                    throw PntCliError.invalidOption(arg)
                }
                inputPaths.append(arg)
            }
        }

        guard !inputPaths.isEmpty else {
            throw PntCliError.missingInput
        }

        let source: BPM?
        if let sourceRaw {
            guard let sourceValue = Double(sourceRaw) else {
                throw PntCliError.invalidBPM(sourceRaw)
            }
            source = try BPM(sourceValue)
        } else {
            source = nil
        }

        let targets = try parseBPMList(targetRaw)
        let outDir = outDirPath.map { URL(fileURLWithPath: $0) }
        let inputs = inputPaths.map { URL(fileURLWithPath: $0) }
        try validateInputFormats(inputs)

        return .render(
            RenderOptions(
                inputs: inputs,
                source: source,
                targets: targets,
                outDir: outDir,
                overwrite: overwrite
            )
        )
    }

    private static func validateInputFormats(_ inputs: [URL]) throws {
        for input in inputs where input.pathExtension.lowercased() == "mp3" {
            throw PntCliError.unsupportedInputFormat(input)
        }
    }
}

public let pntCliVersion = "1.0.0"

public let helpText = """
pnt-cli \(pntCliVersion)
Batch tempo-change songs with Serato Pitch n Time LE.

USAGE:
  pnt-cli <INPUT> [INPUT...] [--source <BPM>] --target <BPM[,BPM...]> [OPTIONS]

EXAMPLES:
  pnt-cli song.wav --source 128 --target 125,122,120
  pnt-cli song.wav --target 125,122,120
  pnt-cli a.wav b.wav c.aiff --source 128 --target 125,122
  pnt-cli -i a.wav -i b.wav --source 128 --target 125,122
  pnt-cli song.aiff --source 120 --target 125,128 --out-dir renders

ARGUMENTS:
  <INPUT> [INPUT...]
      One or more input audio files readable by macOS, such as WAV, AIFF,
      CAF, or M4A. Every input is rendered at every target BPM. Each output
      keeps the same file format as its input.

REQUIRED:
  -t, --target <BPM[,BPM...]>
      Target BPM values to render. Can be comma-separated or repeated.

INPUTS:
  -i, --input <FILE>
      Add an input file. Can be repeated. Combined with positional inputs.

SOURCE:
  -s, --source <BPM>
      Source tempo applied to every input file. If omitted, pnt-cli tries
      to detect it per input from Beatport-purchased tracks only — either
      the ID3 TBPM frame embedded in the file's metadata, or the BPM slot
      in Beatport's filename convention ("..._(Mix)__<BPM>__<Key>.aiff").
      If neither is present for any input, pnt-cli errors out rather than
      guessing.

OUTPUT:
  -d, --out-dir <DIR>
      Output directory. Defaults to the input file directory.

  --overwrite
      Replace existing files.

  Rendered targets automatically copy source track metadata and artwork.
  BPM metadata is updated to match each target BPM when present.

UTILITY:
  -h, --help
      Show this help.

  -v, --version
      Show version.
"""
