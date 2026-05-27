import Foundation

public enum PntCliError: Error, CustomStringConvertible, Equatable {
    case usage(String)
    case missingInput
    case missingSource
    case undetectableSource(URL)
    case missingTargets
    case invalidBPM(String)
    case invalidOption(String)
    case unsupportedInputFormat(URL)
    case outputExists(URL)
    case outputCollision(URL)
    case metadataCopyFailed(URL, URL, String)
    case audioUnitNotFound
    case audioUnitInstantiateFailed(String)
    case missingAudioUnitParameter(String)
    case renderFailed(String)

    public var description: String {
        switch self {
        case .usage(let message):
            return message
        case .missingInput:
            return "missing input audio file"
        case .missingSource:
            return "missing required --source BPM"
        case .undetectableSource(let url):
            return "could not auto-detect source BPM for \(url.lastPathComponent); pass --source <BPM>"
        case .missingTargets:
            return "missing required --target BPM values"
        case .invalidBPM(let value):
            return "invalid BPM value: \(value)"
        case .invalidOption(let option):
            return "invalid option: \(option)"
        case .unsupportedInputFormat(let url):
            return "unsupported input format: \(url.lastPathComponent) (MP3 input is not supported)"
        case .outputExists(let url):
            return "output already exists: \(url.path) (use --overwrite to replace it)"
        case .outputCollision(let url):
            return "multiple inputs would write to the same output: \(url.path) (use --out-dir to disambiguate)"
        case .metadataCopyFailed(let source, let target, let reason):
            return "could not copy metadata from \(source.lastPathComponent) to \(target.lastPathComponent): \(reason)"
        case .audioUnitNotFound:
            return "Serato Pitch n Time LE could not be loaded while processing audio. Install Serato Pitch n Time LE 3.1.1, make sure it is authorized in a DAW or Audio Unit host, then try again."
        case .audioUnitInstantiateFailed(let reason):
            return "Serato Pitch n Time LE failed to load while processing audio: \(reason). Make sure it is installed, authorized, and valid in macOS Audio Units, then try again."
        case .missingAudioUnitParameter(let name):
            return "Serato Pitch n Time LE loaded but is missing the expected \(name) parameter. Reinstall or update Pitch n Time LE 3.1.1, then try again."
        case .renderFailed(let reason):
            return "render failed: \(reason)"
        }
    }
}
