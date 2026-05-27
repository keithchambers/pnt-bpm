import Darwin
import Foundation

public final class Reporter: @unchecked Sendable {
    public struct Plan: Sendable {
        public let tracks: Int
        public let sourceBPMDisplay: String
        public let targets: [BPM]
        public let outDirDisplay: String

        public init(tracks: Int, sourceBPMDisplay: String, targets: [BPM], outDirDisplay: String) {
            self.tracks = tracks
            self.sourceBPMDisplay = sourceBPMDisplay
            self.targets = targets
            self.outDirDisplay = outDirDisplay
        }
    }

    private static let spinnerFrames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    private static let barWidth = 38
    static let clearLiveBlockSequence = "\u{1B}[1A\u{1B}[2K\r\u{1B}[1A\u{1B}[2K\r"

    private let isTTY: Bool
    private let lock = NSLock()

    private var totalRenders = 0
    private var started = 0
    private var completed = 0
    private var failed = 0
    private var skipped = 0
    private var startedAt: Date?
    private var firstError: Error?
    private var timer: DispatchSourceTimer?
    private var spinnerIndex = 0
    private var hasLiveBlock = false

    public init(forceTTY: Bool? = nil) {
        if let forceTTY {
            self.isTTY = forceTTY
        } else {
            self.isTTY = isatty(fileno(stdout)) != 0
        }
    }

    public func printPlan(_ plan: Plan) {
        let targets = plan.targets.map { $0.description }.joined(separator: " ")
        let lines = [
            "Plan",
            "  Tracks       \(plan.tracks)",
            "  Source BPM   \(plan.sourceBPMDisplay)",
            "  Target BPM   \(targets)",
            "  Output dir   \(plan.outDirDisplay)",
            ""
        ]
        print(lines.joined(separator: "\n"))
    }

    public func start(totalRenders: Int) {
        lock.withLock {
            self.totalRenders = totalRenders
            started = 0
            completed = 0
            failed = 0
            skipped = 0
            firstError = nil
            startedAt = Date()
        }
        guard isTTY else { return }

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
        timer.schedule(deadline: .now() + .milliseconds(80), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            self?.redraw()
        }
        timer.resume()
        self.timer = timer
    }

    public func recordStarted() {
        lock.withLock { started += 1 }
    }

    public func recordCompleted() {
        lock.withLock { completed += 1 }
    }

    public func recordFailed(_ error: Error) {
        lock.withLock {
            failed += 1
            if firstError == nil { firstError = error }
        }
    }

    public func recordSkipped() {
        lock.withLock { skipped += 1 }
    }

    @discardableResult
    public func finish() -> Error? {
        timer?.cancel()
        timer = nil
        if isTTY {
            clearLiveBlock()
        }
        printResult()
        return firstFailure
    }

    public var firstFailure: Error? {
        lock.withLock { firstError }
    }

    private func redraw() {
        let snapshot: (done: Int, total: Int, active: Int, fraction: Double, elapsed: TimeInterval, spinner: String)
        lock.lock()
        defer { lock.unlock() }

        guard let started = startedAt, totalRenders > 0 else { return }
        let done = completed + failed + skipped
        let active = max(0, self.started - done)
        let fraction = min(1.0, Double(done) / Double(totalRenders))
        let elapsed = Date().timeIntervalSince(started)
        let spinner = Self.spinnerFrames[spinnerIndex % Self.spinnerFrames.count]
        spinnerIndex += 1
        snapshot = (done, totalRenders, active, fraction, elapsed, spinner)

        let remaining: TimeInterval?
        if snapshot.done > 0 && snapshot.done < snapshot.total {
            let rate = snapshot.elapsed / Double(snapshot.done)
            remaining = rate * Double(snapshot.total - snapshot.done)
        } else {
            remaining = nil
        }

        let line1 = Self.liveStatusLine(
            spinner: snapshot.spinner,
            done: snapshot.done,
            total: snapshot.total,
            active: snapshot.active,
            elapsed: snapshot.elapsed,
            remaining: remaining
        )
        let bar = progressBar(fraction: snapshot.fraction, width: Self.barWidth)
        let pct = Int((snapshot.fraction * 100).rounded())
        let line2 = "   \(bar)  \(pct)%"

        if hasLiveBlock {
            fputs(Self.clearLiveBlockSequence, stdout)
        }
        fputs("\(line1)\n\(line2)\n", stdout)
        fflush(stdout)
        hasLiveBlock = true
    }

    private func clearLiveBlock() {
        lock.lock()
        defer { lock.unlock() }
        guard hasLiveBlock else { return }
        fputs(Self.clearLiveBlockSequence, stdout)
        fflush(stdout)
        hasLiveBlock = false
    }

    private func printResult() {
        let (done, fail, skip, elapsed) = lock.withLock { () -> (Int, Int, Int, TimeInterval) in
            let elapsed = startedAt.map { Date().timeIntervalSince($0) } ?? 0
            return (completed, failed, skipped, elapsed)
        }
        let lines = [
            "Result",
            "  ✓ \(done) rendered     ✗ \(fail) failed     ◌ \(skip) skipped     \(Self.formatResultTime(elapsed))"
        ]
        print(lines.joined(separator: "\n"))
    }

    private func progressBar(fraction: Double, width: Int) -> String {
        let filled = max(0, min(width, Int((fraction * Double(width)).rounded())))
        return String(repeating: "█", count: filled) + String(repeating: "░", count: width - filled)
    }

    static func liveStatusLine(
        spinner: String,
        done: Int,
        total: Int,
        active: Int,
        elapsed: TimeInterval,
        remaining: TimeInterval?
    ) -> String {
        var segments = [
            "\(spinner)  Rendering \(done) of \(total) done"
        ]
        if active > 0 {
            segments.append("\(active) active")
        }
        segments.append("\(formatProgressTime(elapsed)) elapsed")
        if let remaining {
            segments.append("~\(formatProgressTime(remaining)) remaining")
        }
        return segments.joined(separator: " · ")
    }

    private static func formatProgressTime(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    private static func formatResultTime(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let m = total / 60
        let s = total % 60
        if m == 0 { return "\(s)s" }
        return "\(m)m \(String(format: "%02d", s))s"
    }
}
