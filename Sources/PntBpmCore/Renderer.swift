import AVFoundation
import AudioToolbox
import Foundation

public struct RenderResult: Equatable {
    public let outputURL: URL
    public let inputFrames: AVAudioFramePosition
    public let renderedFrames: AVAudioFramePosition
    public let sampleRate: Double
    public let seratoTime: Double
    public let durationRatio: Double

    public var inputDuration: Double {
        Double(inputFrames) / sampleRate
    }

    public var outputDuration: Double {
        Double(renderedFrames) / sampleRate
    }
}

public struct RenderProgress: Equatable {
    public let renderedFrames: AVAudioFramePosition
    public let totalFrames: AVAudioFramePosition

    public var fraction: Double {
        guard totalFrames > 0 else { return 1 }
        return min(1, Double(renderedFrames) / Double(totalFrames))
    }
}

public final class PitchNTimeRenderer {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func render(
        plan: OutputPlan,
        overwrite: Bool,
        gain: Float,
        tailMilliseconds: Double,
        progress: ((RenderProgress) -> Void)? = nil
    ) throws -> RenderResult {
        if fileManager.fileExists(atPath: plan.outputURL.path) {
            guard overwrite else {
                throw PntBpmError.outputExists(plan.outputURL)
            }
            try fileManager.removeItem(at: plan.outputURL)
        }

        try fileManager.createDirectory(
            at: plan.outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let inputFile = try AVAudioFile(forReading: plan.input)
        let processingFormat = inputFile.processingFormat
        let pnt = try PitchNTimeAudioUnit.instantiate()

        try PitchNTimeAudioUnit.configure(
            pnt,
            time: plan.ratios.seratoTime,
            gain: gain
        )

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()

        engine.attach(player)
        engine.attach(pnt)
        engine.connect(player, to: pnt, format: processingFormat)
        engine.connect(pnt, to: engine.mainMixerNode, format: processingFormat)

        try engine.enableManualRenderingMode(
            .offline,
            format: processingFormat,
            maximumFrameCount: 4096
        )

        let outputSettings = try wavSettings(for: processingFormat)
        let outputFile = try AVAudioFile(
            forWriting: plan.outputURL,
            settings: outputSettings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        let tailFrames = AVAudioFramePosition((tailMilliseconds / 1000.0 * processingFormat.sampleRate).rounded(.up))
        let targetFrames = AVAudioFramePosition(
            (Double(inputFile.length) * plan.ratios.outputDurationRatio).rounded(.up)
        ) + tailFrames

        guard let renderBuffer = AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat,
            frameCapacity: engine.manualRenderingMaximumFrameCount
        ) else {
            throw PntBpmError.renderFailed("could not allocate render buffer")
        }

        try engine.start()
        player.scheduleFile(inputFile, at: nil)
        player.play()

        var renderedFrames: AVAudioFramePosition = 0
        progress?(RenderProgress(renderedFrames: renderedFrames, totalFrames: targetFrames))

        while renderedFrames < targetFrames {
            let remaining = targetFrames - renderedFrames
            let frameCount = min(AVAudioFrameCount(remaining), engine.manualRenderingMaximumFrameCount)
            let status = try engine.renderOffline(frameCount, to: renderBuffer)

            switch status {
            case .success:
                try outputFile.write(from: renderBuffer)
                renderedFrames += AVAudioFramePosition(renderBuffer.frameLength)
                progress?(RenderProgress(renderedFrames: renderedFrames, totalFrames: targetFrames))
            case .insufficientDataFromInputNode:
                continue
            case .cannotDoInCurrentContext:
                continue
            case .error:
                throw PntBpmError.renderFailed("AVAudioEngine manual render returned an error")
            @unknown default:
                throw PntBpmError.renderFailed("AVAudioEngine manual render returned an unknown status")
            }
        }

        player.stop()
        engine.stop()

        return RenderResult(
            outputURL: plan.outputURL,
            inputFrames: inputFile.length,
            renderedFrames: renderedFrames,
            sampleRate: processingFormat.sampleRate,
            seratoTime: plan.ratios.seratoTime,
            durationRatio: plan.ratios.outputDurationRatio
        )
    }

    private func wavSettings(for format: AVAudioFormat) throws -> [String: Any] {
        let channelCount = Int(format.channelCount)
        guard channelCount > 0 else {
            throw PntBpmError.renderFailed("input has no audio channels")
        }

        return [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
    }
}
