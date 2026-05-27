import Foundation

public struct BPM: Equatable, Comparable, CustomStringConvertible {
    public let value: Double

    public init(_ value: Double) throws {
        guard value.isFinite, value > 0, value <= 999 else {
            throw PntBpmError.invalidBPM(String(value))
        }
        self.value = value
    }

    public static func < (lhs: BPM, rhs: BPM) -> Bool {
        lhs.value < rhs.value
    }

    public var description: String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.3f", value)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }
}

public struct TempoRatios: Equatable {
    public let source: BPM
    public let target: BPM

    public init(source: BPM, target: BPM) {
        self.source = source
        self.target = target
    }

    public var seratoTime: Double {
        target.value / source.value
    }

    public var outputDurationRatio: Double {
        source.value / target.value
    }
}

public func parseBPMList(_ values: [String]) throws -> [BPM] {
    var targets: [BPM] = []

    for raw in values {
        let pieces = raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !pieces.isEmpty else {
            throw PntBpmError.invalidBPM(raw)
        }

        for piece in pieces {
            guard let value = Double(piece) else {
                throw PntBpmError.invalidBPM(piece)
            }
            targets.append(try BPM(value))
        }
    }

    guard !targets.isEmpty else {
        throw PntBpmError.missingTargets
    }

    return targets
}
