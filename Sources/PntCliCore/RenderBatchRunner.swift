import Foundation

public enum RenderBatchRunner {
    public static func render(
        plans: [OutputPlan],
        jobs: Int,
        render: @escaping @Sendable (OutputPlan) throws -> RenderResult
    ) throws -> [RenderResult] {
        try BoundedWorkRunner.run(plans, jobs: jobs, work: render)
    }

    /// Run `body` for each plan with up to `jobs` workers, continuing past per-item failures.
    /// The body is responsible for handling its own errors (e.g. recording them on a reporter).
    public static func forEach(
        plans: [OutputPlan],
        jobs: Int,
        body: @escaping @Sendable (OutputPlan) -> Void
    ) {
        guard !plans.isEmpty else { return }
        let workerCount = max(1, min(jobs, plans.count))

        if workerCount == 1 {
            plans.forEach(body)
            return
        }

        let cursor = WorkCursor(count: plans.count)
        let group = DispatchGroup()

        for _ in 0..<workerCount {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { group.leave() }
                while let i = cursor.next() {
                    body(plans[i])
                }
            }
        }

        group.wait()
    }
}

private final class WorkCursor: @unchecked Sendable {
    private let lock = NSLock()
    private let count: Int
    private var index = 0

    init(count: Int) { self.count = count }

    func next() -> Int? {
        lock.withLock {
            guard index < count else { return nil }
            let i = index
            index += 1
            return i
        }
    }
}

enum BoundedWorkRunner {
    static func run<Input: Sendable, Output: Sendable>(
        _ inputs: [Input],
        jobs: Int,
        work: @escaping @Sendable (Input) throws -> Output
    ) throws -> [Output] {
        precondition(jobs > 0, "jobs must be positive")
        guard !inputs.isEmpty else { return [] }

        if jobs == 1 {
            return try inputs.map(work)
        }

        let state = BoundedWorkState<Input, Output>(inputs: inputs)
        let workerCount = min(jobs, inputs.count)
        let group = DispatchGroup()

        for _ in 0..<workerCount {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { group.leave() }

                while let claimed = state.claimNext() {
                    do {
                        let output = try work(claimed.input)
                        state.store(output, at: claimed.index)
                    } catch {
                        state.record(error)
                        return
                    }
                }
            }
        }

        group.wait()
        if let error = state.firstError {
            throw error
        }
        return state.orderedResults()
    }
}

private final class BoundedWorkState<Input: Sendable, Output: Sendable>: @unchecked Sendable {
    private let inputs: [Input]
    private let lock = NSLock()
    private var nextIndex = 0
    private var results: [Output?]
    private var storedError: Error?

    init(inputs: [Input]) {
        self.inputs = inputs
        self.results = Array(repeating: nil, count: inputs.count)
    }

    var firstError: Error? {
        lock.withLock { storedError }
    }

    func claimNext() -> (index: Int, input: Input)? {
        lock.withLock {
            guard storedError == nil, nextIndex < inputs.count else {
                return nil
            }

            let index = nextIndex
            nextIndex += 1
            return (index, inputs[index])
        }
    }

    func store(_ output: Output, at index: Int) {
        lock.withLock {
            results[index] = output
        }
    }

    func record(_ error: Error) {
        lock.withLock {
            if storedError == nil {
                storedError = error
            }
        }
    }

    func orderedResults() -> [Output] {
        lock.withLock {
            results.map { $0! }
        }
    }
}
