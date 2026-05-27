import Foundation

public enum Command: Equatable {
    case render(RenderOptions)
    case doctor(verbose: Bool)
    case help
    case version
}

public struct RenderOptions: Equatable {
    public var input: URL
    /// Source BPM. nil means "auto-detect from the input file".
    public var source: BPM?
    public var targets: [BPM]
    public var outDir: URL?
    public var format: String
    public var nameTemplate: String
    public var overwrite: Bool
    public var dryRun: Bool
    public var verbose: Bool
    public var gain: Float
    public var tailMilliseconds: Double

    public init(
        input: URL,
        source: BPM?,
        targets: [BPM],
        outDir: URL? = nil,
        format: String = "wav",
        nameTemplate: String = "{title}_{bpm}bpm.{ext}",
        overwrite: Bool = false,
        dryRun: Bool = false,
        verbose: Bool = false,
        gain: Float = 1.0,
        tailMilliseconds: Double = 0
    ) {
        self.input = input
        self.source = source
        self.targets = targets
        self.outDir = outDir
        self.format = format
        self.nameTemplate = nameTemplate
        self.overwrite = overwrite
        self.dryRun = dryRun
        self.verbose = verbose
        self.gain = gain
        self.tailMilliseconds = tailMilliseconds
    }
}

public struct CLIParser {
    public static func parse(_ arguments: [String]) throws -> Command {
        var args = Array(arguments.dropFirst())
        if args.isEmpty {
            return .help
        }

        var inputPath: String?
        var sourceRaw: String?
        var targetRaw: [String] = []
        var outDirPath: String?
        var format = "wav"
        var nameTemplate = "{title}_{bpm}bpm.{ext}"
        var overwrite = false
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
                guard inputPath == nil else {
                    throw PntBpmError.usage("only one input audio file can be provided")
                }
                inputPath = arg
            }
        }

        guard let inputPath else {
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

        return .render(
            RenderOptions(
                input: URL(fileURLWithPath: inputPath),
                source: source,
                targets: targets,
                outDir: outDir,
                format: format,
                nameTemplate: nameTemplate,
                overwrite: overwrite,
                dryRun: dryRun,
                verbose: verbose,
                gain: gain,
                tailMilliseconds: tailMilliseconds
            )
        )
    }
}

public let pntBpmVersion = "0.1.0"

public let helpText = """
pnt-bpm \(pntBpmVersion)
Batch tempo-change songs with Serato Pitch n Time LE.

USAGE:
  pnt-bpm <INPUT> [--source <BPM>] --target <BPM[,BPM...]> [OPTIONS]

EXAMPLES:
  pnt-bpm song.wav --source 128 --target 125,122,120
  pnt-bpm song.wav --target 125,122,120                 # auto-detect source BPM
  pnt-bpm song.aiff --source 120 --target 125,128 --out-dir renders

ARGUMENTS:
  <INPUT>
      Input audio file readable by macOS, such as WAV, AIFF, CAF, MP3, or M4A.

REQUIRED:
  -t, --target <BPM[,BPM...]>
      Target BPM values to render. Can be comma-separated or repeated.

  --output <BPM[,BPM...]>
      Alias for --target.

SOURCE:
  -s, --source <BPM>
      Source tempo of the input song. If omitted, pnt-bpm tries to detect
      it from embedded metadata (ID3 TBPM, iTunes tmpo), the input
      filename (Beatport "__BPM__" pattern), or up to three parent
      directory names (mvsep-style "...-original-mix-125-bb-minor").

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
