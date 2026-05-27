@preconcurrency import AVFoundation
import AudioToolbox
import Foundation

public enum PitchNTimeAudioUnit {
    public static let pitchAddress: AUParameterAddress = 0
    public static let timeAddress: AUParameterAddress = 1
    public static let gainAddress: AUParameterAddress = 2

    public static func isAvailable() -> Bool {
        do {
            _ = try instantiate()
            return true
        } catch {
            return false
        }
    }

    public static func instantiate() throws -> AVAudioUnit {
        let description = AudioComponentDescription(
            componentType: kAudioUnitType_FormatConverter,
            componentSubType: fourCC("PnTm"),
            componentManufacturer: fourCC("Srto"),
            componentFlags: 0,
            componentFlagsMask: 0
        )

        var mutableDescription = description
        guard AudioComponentFindNext(nil, &mutableDescription) != nil else {
            throw PntCliError.audioUnitNotFound
        }

        let semaphore = DispatchSemaphore(value: 0)
        let result = AudioUnitInstantiationResult()

        AVAudioUnit.instantiate(with: description, options: []) { unit, error in
            result.set(unit: unit, error: error)
            semaphore.signal()
        }

        semaphore.wait()

        guard let unit = result.unit else {
            throw PntCliError.audioUnitInstantiateFailed(result.error?.localizedDescription ?? "unknown error")
        }

        try verifyRequiredParameters(unit)
        return unit
    }

    public static func configure(_ unit: AVAudioUnit, time: Double, gain: Float) throws {
        guard let pitchParameter = unit.auAudioUnit.parameterTree?.parameter(withAddress: pitchAddress) else {
            throw PntCliError.missingAudioUnitParameter("Pitch")
        }
        guard let timeParameter = unit.auAudioUnit.parameterTree?.parameter(withAddress: timeAddress) else {
            throw PntCliError.missingAudioUnitParameter("Time")
        }
        guard let gainParameter = unit.auAudioUnit.parameterTree?.parameter(withAddress: gainAddress) else {
            throw PntCliError.missingAudioUnitParameter("Gain")
        }

        // Pitch n Time exposes pitch as a percentage; 100 = no pitch change.
        pitchParameter.value = 100.0
        timeParameter.value = Float(time)
        gainParameter.value = gain
    }

    private static func verifyRequiredParameters(_ unit: AVAudioUnit) throws {
        let tree = unit.auAudioUnit.parameterTree
        if tree?.parameter(withAddress: pitchAddress) == nil {
            throw PntCliError.missingAudioUnitParameter("Pitch")
        }
        if tree?.parameter(withAddress: timeAddress) == nil {
            throw PntCliError.missingAudioUnitParameter("Time")
        }
        if tree?.parameter(withAddress: gainAddress) == nil {
            throw PntCliError.missingAudioUnitParameter("Gain")
        }
    }

    private static func fourCC(_ string: String) -> OSType {
        precondition(string.utf8.count == 4)
        return string.utf8.reduce(OSType(0)) { ($0 << 8) | OSType($1) }
    }
}

private final class AudioUnitInstantiationResult: @unchecked Sendable {
    private let lock = NSLock()
    private var storedUnit: AVAudioUnit?
    private var storedError: Error?

    var unit: AVAudioUnit? {
        lock.withLock { storedUnit }
    }

    var error: Error? {
        lock.withLock { storedError }
    }

    func set(unit: AVAudioUnit?, error: Error?) {
        lock.withLock {
            storedUnit = unit
            storedError = error
        }
    }
}
