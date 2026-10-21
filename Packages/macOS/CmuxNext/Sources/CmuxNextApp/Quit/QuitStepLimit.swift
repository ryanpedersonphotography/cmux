import CmuxNextWakeups
import os

/// One quit step under a time limit (slow quit, 2026-10-20): the quit goes on
/// when the step ends or when its limit passes, whichever comes first. A step
/// past its limit keeps running; the process still ends at the quit's hard
/// deadline (`QuitDeadline`), so no step can hold a quit.
///
/// A step that blocks the main thread cannot be raced here (the limit fires on
/// the main actor too): `QuitDeadline`'s own thread ends the process then.
@MainActor
final class QuitStepLimit {
    private var continuation: CheckedContinuation<Bool, Never>?
    private let timer: DemandTimer

    private init(_ name: String, clock: any Clock<Duration>) {
        timer = DemandTimer(owner: "quit.\(name)", clock: clock)
    }

    /// Runs `step`; true when it ended within `limit`.
    @discardableResult
    static func run(_ name: String, limit: Duration, clock: any Clock<Duration> = ContinuousClock(),
                    _ step: @escaping @MainActor () async -> Void) async -> Bool {
        let race = QuitStepLimit(name, clock: clock)
        let ended = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            race.continuation = continuation
            race.timer.schedule(after: limit) { @MainActor in race.finish(false) }
            // task-owner: one quit step; it may outlive its limit, and the process ends at the quit deadline.
            Task { @MainActor in
                await step()
                race.finish(true)
            }
        }
        DebugTimings.markLaunch(ended ? "quit.\(name)" : "quit.\(name).limit")
        if !ended {
            Logger(subsystem: "com.cmuxterm.app.next", category: "app.quit")
                .error("quit step \(name, privacy: .public) passed its \(limit, privacy: .public) limit; the quit goes on")
        }
        return ended
    }

    private func finish(_ ended: Bool) {
        timer.cancel()
        continuation?.resume(returning: ended)
        continuation = nil
    }
}
