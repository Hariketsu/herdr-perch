import Foundation
import Testing
import PerchCore

private actor ManualSleep {
    private var pending: [CheckedContinuation<Void, Never>] = []
    private(set) var durations: [Duration] = []
    private var automatic = false

    func sleep(_ duration: Duration) async {
        durations.append(duration)
        if automatic { return }
        await withCheckedContinuation { pending.append($0) }
    }
    var waiting: Int { pending.count }
    func release() {
        let current = pending
        pending.removeAll()
        current.forEach { $0.resume() }
    }
    func finish() {
        automatic = true
        release()
    }
}

private actor FetchProbe {
    private(set) var count = 0
    private(set) var active = 0
    private(set) var maximum = 0
    private var firstGate: CheckedContinuation<Void, Never>?
    private let blockFirst: Bool
    private var released = false
    init(blockFirst: Bool = false) { self.blockFirst = blockFirst }

    func fetch() async {
        count += 1
        active += 1
        maximum = max(maximum, active)
        if blockFirst && count == 1 && !released {
            await withCheckedContinuation { firstGate = $0 }
        }
        active -= 1
    }
    func release() {
        released = true
        firstGate?.resume()
        firstGate = nil
    }
}

private actor CompletionFlag {
    var done = false
    func mark() { done = true }
}

/// Keep a broken drain implementation from hanging the test runner indefinitely.
private func boundedDrain(_ scheduler: RefreshScheduler) async {
    let flag = CompletionFlag()
    let task = Task {
        await scheduler.drain()
        await flag.mark()
    }
    _ = await eventually { await flag.done }
    task.cancel()
}

@Suite struct RefreshSchedulerTests {
    @Test func singleRequestAndDefaultCoalesce() async {
        let clock = ManualSleep()
        let probe = FetchProbe()
        let scheduler = RefreshScheduler(sleep: { await clock.sleep($0) }, fetch: { await probe.fetch() })
        await scheduler.request()
        guard await eventually({ await clock.waiting == 1 }) else { await clock.finish(); return }
        #expect(await probe.count == 0)
        #expect(await clock.durations == [.milliseconds(50)])
        await clock.finish()
        await boundedDrain(scheduler)
        #expect(await probe.count == 1)
        #expect(await probe.maximum == 1)
        await boundedDrain(scheduler)
        #expect(await probe.count == 1)
    }

    @Test func tenRequestsInWindowCoalesce() async {
        let clock = ManualSleep()
        let probe = FetchProbe()
        let scheduler = RefreshScheduler(coalesce: .milliseconds(17), sleep: { await clock.sleep($0) }, fetch: { await probe.fetch() })
        await scheduler.request()
        guard await eventually({ await clock.waiting == 1 }) else { await clock.finish(); return }
        for _ in 0..<9 { await scheduler.request() }
        #expect(await probe.count == 0)
        await clock.finish()
        await boundedDrain(scheduler)
        #expect(await clock.durations == [.milliseconds(17)])
        #expect(await probe.count == 1)
    }

    @Test func fiveRequestsDuringFetchQueueExactlyOneSerialFetch() async {
        let clock = ManualSleep()
        let probe = FetchProbe(blockFirst: true)
        let scheduler = RefreshScheduler(sleep: { await clock.sleep($0) }, fetch: { await probe.fetch() })
        await clock.finish()
        await scheduler.request()
        guard await eventually({ await probe.active == 1 }) else { await probe.release(); return }
        for _ in 0..<5 { await scheduler.request() }
        #expect(await probe.count == 1)
        #expect(await probe.maximum == 1)
        await probe.release()
        await boundedDrain(scheduler)
        #expect(await probe.count == 2)
        #expect(await probe.active == 0)
        #expect(await probe.maximum == 1)
    }

    @Test func drainWaitsForQueuedAndActiveWork() async {
        let clock = ManualSleep()
        let probe = FetchProbe(blockFirst: true)
        let scheduler = RefreshScheduler(sleep: { await clock.sleep($0) }, fetch: { await probe.fetch() })
        await scheduler.request()
        guard await eventually({ await clock.waiting == 1 }) else { await clock.finish(); return }
        let entered = CompletionFlag()
        let completed = CompletionFlag()
        let drain = Task {
            await entered.mark()
            await scheduler.drain()
            await completed.mark()
        }
        guard await eventually({ await entered.done }) else {
            await clock.finish(); await probe.release(); drain.cancel(); return
        }
        #expect(await completed.done == false)
        await clock.finish()
        guard await eventually({ await probe.active == 1 }) else { await probe.release(); drain.cancel(); return }
        #expect(await completed.done == false)
        await scheduler.request()
        await probe.release()
        _ = await eventually { await completed.done }
        drain.cancel()
        #expect(await probe.count == 2)
        #expect(await probe.maximum == 1)
    }
}
