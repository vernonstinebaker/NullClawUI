import Foundation
import Observation

// MARK: - GatewayHealthMonitor

/// Phase 13: Periodic gateway health monitoring.
///
/// Polls GET /health on a fixed interval (default 30 s) while the app is in the
/// foreground. When the gateway goes offline, `AppModel.connectionStatus` is set
/// to `.offline`; on recovery it is set to `.online` and any pending SSE stream
/// resume is triggered via the supplied callback.
///
/// - Thread-safety: all state is confined to `@MainActor`. Timer callbacks
///   hop back to the main actor before touching any state.
/// - The monitor owns no URLSession — it delegates health checks to the supplied
///   `InstanceGatewayClient`, which already has its own session management.
///
/// ## onReconnect vs. initial online transition
///
/// `onReconnect` fires **only** when a successful health check follows at least
/// one recorded failure (`consecutiveFailures > 0` before the tick). It does NOT
/// fire on the very first successful tick when the app launches into `.unknown`
/// status — that transition is handled by the initial `GatewayViewModel.connect()`
/// call in `NullClawUIApp.setupGateway()`. This keeps the SSE-resume logic
/// conservative: only genuine outage-then-recovery events trigger a stream restart.
@Observable
@MainActor
final class GatewayHealthMonitor {
    // MARK: - Configuration

    /// Interval between health-check polls (seconds). Overridable for testing.
    var pollInterval: TimeInterval

    // MARK: - State (observable)

    /// Number of consecutive failed health checks since the last successful one.
    private(set) var consecutiveFailures: Int = 0

    // MARK: - Private

    private var appModel: AppModel
    private var clientProvider: @MainActor () -> InstanceGatewayClient
    private var onReconnect: (@MainActor () -> Void)?

    private var timerTask: Task<Void, Never>?
    private var checkNowTask: Task<Void, Never>?
    private var isRunning: Bool = false

    // MARK: - Init

    /// - Parameters:
    ///   - appModel: The shared app state whose `connectionStatus` will be updated.
    ///   - clientProvider: Returns the *current* `InstanceGatewayClient`. Called on every
    ///     poll tick so gateway switches are automatically picked up.
    ///   - pollInterval: How often to check health. Default 30 s.
    ///   - onReconnect: Called on the main actor immediately after a successful
    ///     health check that follows at least one recorded failure — use this to
    ///     resume an interrupted SSE stream. Not called on the first successful tick
    ///     from `.unknown` status (app launch).
    init(
        appModel: AppModel,
        clientProvider: @escaping @MainActor () -> InstanceGatewayClient,
        pollInterval: TimeInterval = 30,
        onReconnect: (@MainActor () -> Void)? = nil
    ) {
        self.appModel = appModel
        self.clientProvider = clientProvider
        self.pollInterval = pollInterval
        self.onReconnect = onReconnect
    }

    // MARK: - Lifecycle

    /// Starts the polling loop. Safe to call multiple times — a running loop is
    /// stopped first so there is never more than one active timer.
    func start() {
        stop()
        isRunning = true
        timerTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await tick()
                // Sleep for pollInterval, but wake up for cancellation every second.
                let ticks = max(1, Int(pollInterval))
                for _ in 0 ..< ticks {
                    if Task.isCancelled { return }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }
    }

    /// Stops the polling loop. The in-flight check (if any) completes normally but
    /// its result is discarded after the task is cancelled.
    func stop() {
        timerTask?.cancel()
        timerTask = nil
        checkNowTask?.cancel()
        checkNowTask = nil
        isRunning = false
    }

    // MARK: - Manual trigger

    /// Performs an immediate health check outside the normal timer cycle.
    /// Used when the app returns to the foreground so the status updates instantly
    /// rather than waiting for the next tick.
    func checkNow() {
        checkNowTask?.cancel()
        checkNowTask = Task { [weak self] in
            await self?.tick()
        }
    }

    // MARK: - Internal poll

    private func tick() async {
        let client = clientProvider()
        // Capture the pre-tick failure count before mutating state.
        let hadPriorFailure = consecutiveFailures > 0
        // Track whether status was not yet known (initial launch) vs. a real outage.
        let wasOffline = appModel.connectionStatus != .online
        do {
            try await client.checkHealth()
            // Success — mark online and reset the failure counter.
            consecutiveFailures = 0
            appModel.connectionStatus = .online

            // Always refresh the agent card when coming from any non-online state
            // (covers both the initial .unknown → .online transition at launch and
            // genuine outage-then-recovery). This keeps the title / accent colour
            // up-to-date without an extra explicit fetch in setupGateway().
            if wasOffline || hadPriorFailure {
                if let card = try? await client.fetchAgentCard() {
                    appModel.agentCard = card
                }
            }

            // Fire the reconnect callback ONLY when a real outage occurred (i.e. at
            // least one failure was recorded before this successful tick). Prevents
            // spuriously restarting an SSE stream on the very first health poll after
            // app launch when connectionStatus is still .unknown.
            if hadPriorFailure {
                onReconnect?()
            }
        } catch {
            consecutiveFailures += 1
            appModel.connectionStatus = .offline
            // Nil the live card so effectiveAgentCard falls back to the cache.
            if consecutiveFailures == 1 {
                appModel.agentCard = nil
            }
        }
    }
}
