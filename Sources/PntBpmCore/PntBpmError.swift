import Foundation

public enum PntBpmError: Error, CustomStringConvertible, Equatable {
    case usage(String)
    case missingInput
    case missingSource
    case undetectableSource(URL)
    case missingTargets
    case invalidBPM(String)
    case invalidOption(String)
    case unsupportedInputFormat(URL)
    case unsupportedFormat(String)
    case outputExists(URL)
    case outputCollision(URL)
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
            return "missing required --target/--output BPM values"
        case .invalidBPM(let value):
            return "invalid BPM value: \(value)"
        case .invalidOption(let option):
            return "invalid option: \(option)"
        case .unsupportedInputFormat(let url):
            return "unsupported input format: \(url.lastPathComponent) (MP3 input is not supported)"
        case .unsupportedFormat(let format):
            return "unsupported output format: \(format)"
        case .outputExists(let url):
            return "output already exists: \(url.path) (use --overwrite to replace it)"
        case .outputCollision(let url):
            return "multiple inputs would write to the same output: \(url.path) (use --name-template or --out-dir to disambiguate)"
        case .audioUnitNotFound:
            return "Serato Pitch n Time LE Audio Unit was not found"
        case .audioUnitInstantiateFailed(let reason):
            return "could not load Serato Pitch n Time LE: \(reason)"
        case .missingAudioUnitParameter(let name):
            return "Serato Pitch n Time LE is missing parameter: \(name)"
        case .renderFailed(let reason):
            return "render failed: \(reason)"
        }
    }
}
