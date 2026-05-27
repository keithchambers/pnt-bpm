import Foundation

public enum Command: Equatable {
    case render(RenderOptions)
    case doctor(verbose: Bool)
    case help
    case version
}

public struct RenderOptions: Equatable {
    public var inputs: [URL]
    /// Source BPM applied to every input. nil means "auto-detect per input".
    public var source: BPM?
    public var targets: [BPM]
    public var outDir: URL?
    public var format: String
    public var nameTemplate: String
    public var overwrite: Bool
    public var copyMetadata: Bool
    public var dryRun: Bool
    public var verbose: Bool
    public var gain: Float
    public var tailMilliseconds: Double

    public var input: URL {
        inputs[0]
    }

    public init(
        inputs: [URL],
        source: BPM?,
        targets: [BPM],
        outDir: URL? = nil,
        format: String = "wav",
        nameTemplate: String = "{title}_{bpm}bpm.{ext}",
        overwrite: Bool = false,
        copyMetadata: Bool = false,
        dryRun: Bool = false,
        verbose: Bool = false,
        gain: Float = 1.0,
        tailMilliseconds: Double = 0
    ) {
        self.inputs = inputs
        self.source = source
        self.targets = targets
        self.outDir = outDir
        self.format = format
        self.nameTemplate = nameTemplate
        self.overwrite = overwrite
        self.copyMetadata = copyMetadata
        self.dryRun = dryRun
        self.verbose = verbose
        self.gain = gain
        self.tailMilliseconds = tailMilliseconds
    }

    public init(
        input: URL,
        source: BPM?,
        targets: [BPM],
        outDir: URL? = nil,
        format: String = "wav",
        nameTemplate: String = "{title}_{bpm}bpm.{ext}",
        overwrite: Bool = false,
        copyMetadata: Bool = false,
        dryRun: Bool = false,
        verbose: Bool = false,
        gain: Float = 1.0,
        tailMilliseconds: Double = 0
    ) {
        self.init(
            inputs: [input],
            source: source,
            targets: targets,
            outDir: outDir,
            format: format,
            nameTemplate: nameTemplate,
            overwrite: overwrite,
            copyMetadata: copyMetadata,
            dryRun: dryRun,
            verbose: verbose,
            gain: gain,
            tailMilliseconds: tailMilliseconds
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
        var format = "wav"
        var nameTemplate = "{title}_{bpm}bpm.{ext}"
        var overwrite = false
        var copyMetadata = false
        var dryRun = false
        var verbose = false
        var gain: Float = 1.0
        var tailMilliseconds: Double = 0

        func popValue(after option: String) throws -> String {
            guard !args.isEmpty else {
                throw PntBpmError.usage("\(option) requires a value")
            }
            return args.removeFirst()
        }

        while !args.isEmpty {
            let arg = args.removeFirst()
            switch arg {
            case "-h", "--help":
                return .help
            case "--version":
                return .version
            case "--doctor":
                return .doctor(verbose: verbose || args.contains("--verbose"))
            case "-i", "--input":
                inputPaths.append(try popValue(after: arg))
            case "-s", "--source":
                sourceRaw = try popValue(after: arg)
            case "-t", "--target", "--output":
                targetRaw.append(try popValue(after: arg))
            case "-d", "--out-dir":
                outDirPath = try popValue(after: arg)
            case "--format":
                format = try popValue(after: arg)
            case "--name-template":
                nameTemplate = try popValue(after: arg)
            case "--overwrite":
                overwrite = true
            case "--copy-metadata":
                copyMetadata = true
            case "--dry-run":
                dryRun = true
            case "--verbose":
                verbose = true
            case "--gain":
                let raw = try popValue(after: arg)
                guard let parsed = Float(raw), parsed.isFinite, parsed >= 0, parsed <= 2 else {
                    throw PntBpmError.usage("--gain must be a number from 0 to 2")
                }
                gain = parsed
            case "--tail-ms":
                let raw = try popValue(after: arg)
                guard let parsed = Double(raw), parsed.isFinite, parsed >= 0 else {
                    throw PntBpmError.usage("--tail-ms must be a non-negative number")
                }
                tailMilliseconds = parsed
            default:
                if arg.hasPrefix("-") {
                    throw PntBpmError.invalidOption(arg)
                }
                inputPaths.append(arg)
            }
        }

        guard !inputPaths.isEmpty else {
            throw PntBpmError.missingInput
        }

        let source: BPM?
        if let sourceRaw {
            guard let sourceValue = Double(sourceRaw) else {
                throw PntBpmError.invalidBPM(sourceRaw)
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
                format: format,
                nameTemplate: nameTemplate,
                overwrite: overwrite,
                copyMetadata: copyMetadata,
                dryRun: dryRun,
                verbose: verbose,
                gain: gain,
                tailMilliseconds: tailMilliseconds
            )
        )
    }

    private static func validateInputFormats(_ inputs: [URL]) throws {
        for input in inputs where input.pathExtension.lowercased() == "mp3" {
            throw PntBpmError.unsupportedInputFormat(input)
        }
    }
}

public let pntBpmVersion = "1.0.0"

public let helpText = """
pnt-bpm \(pntBpmVersion)
Batch tempo-change songs with Serato Pitch n Time LE.

USAGE:
  pnt-bpm <INPUT> [INPUT...] [--source <BPM>] --target <BPM[,BPM...]> [OPTIONS]

EXAMPLES:
  pnt-bpm song.wav --source 128 --target 125,122,120
  pnt-bpm song.wav --target 125,122,120                 # auto-detect source BPM
  pnt-bpm a.wav b.wav c.aiff --source 128 --target 125,122
  pnt-bpm -i a.wav -i b.wav --source 128 --target 125,122
  pnt-bpm song.aiff --source 120 --target 125,128 --out-dir renders

ARGUMENTS:
  <INPUT> [INPUT...]
      One or more input audio files readable by macOS, such as WAV, AIFF,
      CAF, or M4A. Every input is rendered at every target BPM.

REQUIRED:
  -t, --target <BPM[,BPM...]>
      Target BPM values to render. Can be comma-separated or repeated.

  --output <BPM[,BPM...]>
      Alias for --target.

INPUTS:
  -i, --input <FILE>
      Add an input file. Can be repeated. Combined with positional inputs.

SOURCE:
  -s, --source <BPM>
      Source tempo applied to every input file. If omitted, pnt-bpm tries
      to detect it per input from Beatport-purchased tracks only — either
      the ID3 TBPM frame embedded in the file's metadata, or the BPM slot
      in Beatport's filename convention ("..._(Mix)__<BPM>__<Key>.aiff").
      If neither is present for any input, pnt-bpm errors out rather than
      guessing.

OUTPUT:
  -d, --out-dir <DIR>
      Output directory. Defaults to the input file directory.

  --name-template <TEMPLATE>
      Output naming pattern.
      Default: {title}_{bpm}bpm.{ext}

  --format <FORMAT>
      Output audio format.
      Default: wav

  --overwrite
      Replace existing files.

  --copy-metadata
      Copy track metadata chunks from each source file to rendered targets,
      including ID3 metadata and embedded artwork when present.

SERATO:
  --gain <VALUE>
      Linear gain sent to Pitch n Time.
      Default: 1.0

  --tail-ms <MS>
      Extra render tail in milliseconds.
      Default: 0

UTILITY:
  --doctor
      Verify Serato Pitch n Time LE can be loaded.

  --dry-run
      Print planned renders without writing files.

  --verbose
      Print ratios, plugin details, and render progress.

  -h, --help
      Show this help.

  --version
      Show version.
"""
