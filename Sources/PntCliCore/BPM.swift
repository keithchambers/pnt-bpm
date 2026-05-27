import Foundation

public struct BPM: Equatable, Comparable, Sendable, CustomStringConvertible {
    public let value: Double
    let decimalValue: Decimal
    fileprivate let rationalValue: PositiveRational

    public init(_ value: Double) throws {
        guard value.isFinite, value > 0, value <= 999 else {
            throw PntCliError.invalidBPM(String(value))
        }
        self.value = value
        let decimalValue = Decimal(string: String(value), locale: Self.locale) ?? Decimal(value)
        self.decimalValue = decimalValue
        self.rationalValue = try Self.rationalValue(from: decimalValue, rawValue: String(value))
    }

    public init(_ rawValue: String) throws {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(trimmed),
              value.isFinite,
              value > 0,
              value <= 999,
              let decimalValue = Decimal(string: trimmed, locale: Self.locale) else {
            throw PntCliError.invalidBPM(rawValue)
        }
        self.value = value
        self.decimalValue = decimalValue
        self.rationalValue = try Self.rationalValue(from: decimalValue, rawValue: rawValue)
    }

    public static func < (lhs: BPM, rhs: BPM) -> Bool {
        lhs.decimalValue < rhs.decimalValue
    }

    public var description: String {
        NSDecimalNumber(decimal: decimalValue).stringValue
    }

    private static let locale = Locale(identifier: "en_US_POSIX")

    private static func rationalValue(from decimalValue: Decimal, rawValue: String) throws -> PositiveRational {
        let normalized = NSDecimalNumber(decimal: decimalValue).stringValue
        do {
            return try PositiveRational(decimalString: normalized)
        } catch {
            throw PntCliError.invalidBPM(rawValue)
        }
    }
}

public struct TempoRatios: Equatable, Sendable {
    public let source: BPM
    public let target: BPM

    public init(source: BPM, target: BPM) {
        self.source = source
        self.target = target
    }

    public var seratoTime: Double {
        NSDecimalNumber(decimal: target.decimalValue / source.decimalValue).doubleValue
    }

    public var outputDurationRatio: Double {
        NSDecimalNumber(decimal: source.decimalValue / target.decimalValue).doubleValue
    }

    public func outputFrameCount(inputFrames: Int64) throws -> Int64 {
        guard inputFrames >= 0 else {
            throw PntCliError.renderFailed("input has a negative frame count")
        }

        return try PositiveRational.ceilingProduct(
            inputFrames,
            source.rationalValue,
            dividedBy: target.rationalValue
        )
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
            throw PntCliError.invalidBPM(raw)
        }

        for piece in pieces {
            targets.append(try BPM(piece))
        }
    }

    guard !targets.isEmpty else {
        throw PntCliError.missingTargets
    }

    return targets
}

private struct PositiveRational: Equatable, Sendable {
    let numerator: Int64
    let denominator: Int64

    init(decimalString: String) throws {
        let trimmed = decimalString.trimmingCharacters(in: .whitespacesAndNewlines)
        let unsigned = trimmed.hasPrefix("+") ? String(trimmed.dropFirst()) : trimmed
        let parts = unsigned.split(separator: ".", omittingEmptySubsequences: false)

        guard parts.count <= 2 else {
            throw PntCliError.invalidBPM(decimalString)
        }

        let whole = parts[0]
        let fraction = parts.count == 2 ? parts[1] : ""
        guard whole.allSatisfy(\.isNumber),
              fraction.allSatisfy(\.isNumber) else {
            throw PntCliError.invalidBPM(decimalString)
        }

        let digits = String(whole) + String(fraction)
        guard let rawNumerator = Int64(digits), rawNumerator > 0 else {
            throw PntCliError.invalidBPM(decimalString)
        }

        var rawDenominator: Int64 = 1
        for _ in fraction {
            let (next, overflow) = rawDenominator.multipliedReportingOverflow(by: 10)
            if overflow {
                throw PntCliError.invalidBPM(decimalString)
            }
            rawDenominator = next
        }

        let divisor = Self.gcd(rawNumerator, rawDenominator)
        numerator = rawNumerator / divisor
        denominator = rawDenominator / divisor
    }

    static func ceilingProduct(
        _ inputFrames: Int64,
        _ source: PositiveRational,
        dividedBy target: PositiveRational
    ) throws -> Int64 {
        var numerators = [inputFrames, source.numerator, target.denominator]
        var denominators = [source.denominator, target.numerator]

        for numeratorIndex in numerators.indices {
            for denominatorIndex in denominators.indices {
                let divisor = gcd(numerators[numeratorIndex], denominators[denominatorIndex])
                if divisor > 1 {
                    numerators[numeratorIndex] /= divisor
                    denominators[denominatorIndex] /= divisor
                }
            }
        }

        let numerator = try checkedProduct(numerators)
        let denominator = try checkedProduct(denominators)
        let quotient = numerator / denominator
        let remainder = numerator % denominator
        let rounded = remainder == 0 ? quotient : quotient + 1

        guard rounded <= Int64.max else {
            throw PntCliError.renderFailed("calculated output is too long")
        }

        return Int64(rounded)
    }

    private static func checkedProduct(_ factors: [Int64]) throws -> UInt64 {
        var product: UInt64 = 1
        for factor in factors where factor != 1 {
            guard factor > 0 else {
                throw PntCliError.renderFailed("calculated output is invalid")
            }
            let (next, overflow) = product.multipliedReportingOverflow(by: UInt64(factor))
            if overflow {
                throw PntCliError.renderFailed("calculated output is too long")
            }
            product = next
        }
        return product
    }

    private static func gcd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        var a = lhs
        var b = rhs
        while b != 0 {
            let remainder = a % b
            a = b
            b = remainder
        }
        return a
    }
}
