import Foundation

public enum PntBpmError: Error, CustomStringConvertible, Equatable {
    case usage(String)
    case missingInput
    case missingSource
    case missingTargets
    case invalidBPM(String)
    case invalidOption(String)
    case unsupportedFormat(String)
    case outputExists(URL)
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
        case .missingTargets:
            return "missing required --target/--output BPM values"
        case .invalidBPM(let value):
            return "invalid BPM value: \(value)"
        case .invalidOption(let option):
            return "invalid option: \(option)"
        case .unsupportedFormat(let format):
            return "unsupported output format: \(format)"
        case .outputExists(let url):
            return "output already exists: \(url.path) (use --overwrite to replace it)"
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
