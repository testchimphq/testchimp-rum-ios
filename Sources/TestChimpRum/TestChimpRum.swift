import Foundation

#if os(iOS)
import UIKit
#endif

// MARK: - Public types

public struct TestChimpRumConfig {
    public var projectId: String
    public var apiKey: String
    public var sessionId: String?
    public var environment: String
    public var release: String?
    public var branchName: String?
    public var sessionMetadata: [String: Any]?
    public var config: Inner?

    public struct Inner {
        public var captureEnabled: Bool?
        public var enableDefaultSessionMetadata: Bool?
        public var maxEventsPerSession: Int?
        public var maxRepeatsPerEvent: Int?
        public var eventSendIntervalMillis: Int?
        public var maxBufferSize: Int?
        public var inactivityTimeoutMillis: Int?
        public var testchimpEndpoint: String?
        public var automationContextTtlSeconds: TimeInterval?

        public init(
            captureEnabled: Bool? = nil,
            enableDefaultSessionMetadata: Bool? = nil,
            maxEventsPerSession: Int? = nil,
            maxRepeatsPerEvent: Int? = nil,
            eventSendIntervalMillis: Int? = nil,
            maxBufferSize: Int? = nil,
            inactivityTimeoutMillis: Int? = nil,
            testchimpEndpoint: String? = nil,
            automationContextTtlSeconds: TimeInterval? = nil
        ) {
            self.captureEnabled = captureEnabled
            self.enableDefaultSessionMetadata = enableDefaultSessionMetadata
            self.maxEventsPerSession = maxEventsPerSession
            self.maxRepeatsPerEvent = maxRepeatsPerEvent
            self.eventSendIntervalMillis = eventSendIntervalMillis
            self.maxBufferSize = maxBufferSize
            self.inactivityTimeoutMillis = inactivityTimeoutMillis
            self.testchimpEndpoint = testchimpEndpoint
            self.automationContextTtlSeconds = automationContextTtlSeconds
        }
    }

    public init(
        projectId: String,
        apiKey: String,
        environment: String,
        sessionId: String? = nil,
        release: String? = nil,
        branchName: String? = nil,
        sessionMetadata: [String: Any]? = nil,
        config: Inner? = nil
    ) {
        self.projectId = projectId
        self.apiKey = apiKey
        self.environment = environment
        self.sessionId = sessionId
        self.release = release
        self.branchName = branchName
        self.sessionMetadata = sessionMetadata
        self.config = config
    }
}

public struct TestChimpEmitInput {
    public var title: String
    public var metadata: [String: Any]?

    public init(title: String, metadata: [String: Any]? = nil) {
        self.title = title
        self.metadata = metadata
    }
}

// MARK: - SDK

public enum TestChimpRum {
    /// HTTP header for {@link com.aware.protos.common.ExecutionPlatform} ordinal (WEB=1, IOS=2, ANDROID=3).
    public static let rumPlatformHeaderName = "testchimp-rum-platform"
    /// IOS (includes macOS targets).
    public static let iosPlatformOrdinal = 2

    private static let lock = NSLock()
    private static var runtime: RumRuntime?

    public static func initialize(_ config: TestChimpRumConfig) {
        guard !config.projectId.isEmpty, !config.apiKey.isEmpty else {
            #if DEBUG
            print("[testchimp-rum] init: projectId and apiKey are required")
            #endif
            return
        }
        lock.lock()
        defer { lock.unlock() }
        runtime?.tearDown()
        let r = RumRuntime(config: config)
        runtime = r
        r.start()
    }

    public static func emit(_ input: TestChimpEmitInput) {
        lock.lock()
        let r = runtime
        lock.unlock()
        guard let r else {
            #if DEBUG
            print("[testchimp-rum] emit: call initialize() first")
            #endif
            return
        }
        r.emit(input)
    }

    /// Drains the in-memory event buffer onto the network queue (synchronous with respect to the RUM serial queue).
    /// Prefer calling this from `scenePhase == .background` / `UIApplication.willResignActiveNotification` so
    /// short Mobilewright runs and app relaunches do not drop buffered events before the process suspends.
    public static func flush() {
        lock.lock()
        let r = runtime
        lock.unlock()
        r?.flush(wait: true)
    }

    public static func getSessionId() -> String {
        lock.lock()
        let r = runtime
        lock.unlock()
        return r?.storedSessionId ?? ""
    }

    /// Clears session + buffer and stops timers (mirrors rum-js `resetSession`); call `initialize` again to resume.
    public static func resetSession() {
        lock.lock()
        let r = runtime
        runtime = nil
        lock.unlock()
        r?.tearDown()
    }

    @discardableResult
    public static func handleAutomationURL(_ url: URL) -> Bool {
        lock.lock()
        let r = runtime
        lock.unlock()
        return r?.handleAutomationURL(url) ?? false
    }

    public static func clearAutomationContext() {
        lock.lock()
        let r = runtime
        lock.unlock()
        r?.clearAutomationContext()
    }
}

// MARK: - Runtime

private final class RumRuntime {
    private let config: TestChimpRumConfig
    private let inner: TestChimpRumConfig.Inner?
    private let sessionStore = SessionStore()
    private let automation = AutomationContext()
    private let queue = DispatchQueue(label: "io.testchimp.rum", qos: .utility)

    private(set) var storedSessionId: String = ""

    private var captureEnabled = true
    private var maxEventsPerSession = 100
    private var maxRepeatsPerEvent = 3
    private var maxBufferSize = 100
    private var eventSendIntervalMs = 10_000
    private var inactivityTimeoutMs: Int64 = 30 * 60 * 1000
    private var baseUrl = "https://ingress.testchimp.io"

    private var flushTimer: DispatchSourceTimer?

    private struct BufferedEvent {
        let title: String
        let timestampMillis: Int64
        let metadata: [String: Any]?
        let eventIndex: Int
        let ciTestInfoSnapshot: String?
    }

    private var buffer: [BufferedEvent] = []

    init(config: TestChimpRumConfig) {
        self.config = config
        inner = config.config
        captureEnabled = inner?.captureEnabled ?? true
        maxEventsPerSession = inner?.maxEventsPerSession ?? 100
        maxRepeatsPerEvent = inner?.maxRepeatsPerEvent ?? 3
        maxBufferSize = inner?.maxBufferSize ?? 100
        eventSendIntervalMs = inner?.eventSendIntervalMillis ?? 10_000
        inactivityTimeoutMs = Int64(inner?.inactivityTimeoutMillis ?? (30 * 60 * 1000))
        if let e = inner?.testchimpEndpoint, !e.isEmpty {
            baseUrl = e.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        if let ttl = inner?.automationContextTtlSeconds, ttl > 0 {
            automation.ttlSeconds = ttl
        }
    }

    func start() {
        let normalizedMeta = RumValidation.normalizeMetadata(config.sessionMetadata)
        let pair = sessionStore.loadOrCreateSessionId(
            proposed: config.sessionId,
            sessionMetadata: normalizedMeta,
            inactivityMs: inactivityTimeoutMs
        )
        storedSessionId = pair.id

        if pair.isNew, captureEnabled {
            queue.sync {
                sendSessionStart()
            }
        }

        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + .milliseconds(eventSendIntervalMs), repeating: .milliseconds(eventSendIntervalMs))
        t.setEventHandler { [weak self] in
            self?.flush(wait: false)
        }
        t.resume()
        flushTimer = t
    }

    func tearDown() {
        flushTimer?.cancel()
        flushTimer = nil
        queue.sync {
            flushLocked()
            sessionStore.clearAll()
            automation.clear()
            buffer.removeAll()
        }
    }

    func handleAutomationURL(_ url: URL) -> Bool {
        if isTrueCoverageClearURL(url) {
            queue.sync {
                flushLocked()
                automation.clear()
            }
            return true
        }
        if isTrueCoverageFlushURL(url) {
            queue.sync {
                flushLocked()
            }
            return true
        }
        return queue.sync {
            AutomationURL.handle(url, context: automation)
        }
    }

    func clearAutomationContext() {
        queue.sync {
            flushLocked()
            automation.clear()
        }
    }

    /// Caller-thread CI snapshot (Playwright / TrueCoverage parity with rum-js), then async buffer + flush.
    func emit(_ input: TestChimpEmitInput) {
        guard captureEnabled else { return }
        guard RumValidation.buildEmitPayload(title: input.title, metadata: input.metadata) != nil else {
            #if DEBUG
            print("[testchimp-rum] Event dropped: validation failed")
            #endif
            return
        }
        let ciSnap = automation.snapshotForEmit()
        queue.async { [weak self] in
            guard let self else { return }
            self.emitOnQueue(input: input, ciSnapshot: ciSnap)
        }
    }

    private func emitOnQueue(input: TestChimpEmitInput, ciSnapshot: String?) {
        sessionStore.touchActivity()

        let title = input.title
        if sessionStore.eventCount() >= maxEventsPerSession {
            return
        }
        var counts = sessionStore.eventTypeCounts()
        if (counts[title] ?? 0) >= maxRepeatsPerEvent {
            return
        }

        let ts = Int64(Date().timeIntervalSince1970 * 1000)
        let meta = RumValidation.normalizeMetadata(input.metadata)

        let next = sessionStore.eventCount() + 1
        sessionStore.setEventCount(next)
        counts[title] = (counts[title] ?? 0) + 1
        sessionStore.setEventTypeCounts(counts)

        buffer.append(
            BufferedEvent(
                title: title,
                timestampMillis: ts,
                metadata: meta,
                eventIndex: next,
                ciTestInfoSnapshot: ciSnapshot
            )
        )

        if buffer.count >= maxBufferSize {
            flushLocked()
        }
    }

    func flush(wait: Bool) {
        if wait {
            queue.sync { flushLocked() }
        } else {
            queue.async { [weak self] in
                self?.flushLocked()
            }
        }
    }

    private func flushLocked() {
        guard !buffer.isEmpty else { return }
        let batch = buffer
        buffer = []
        postEvents(batch)
    }

    private func sendSessionStart() {
        var meta: [String: Any] = [:]
        if inner?.enableDefaultSessionMetadata ?? true {
            meta.merge(DefaultSessionMetadata.dictionaryForSessionStart()) { _, new in new }
        }
        if let stored = sessionStore.sessionMetadata() {
            meta.merge(stored) { _, new in new }
        }

        var body: [String: Any] = [
            "session_id": storedSessionId,
            "started_at": Int64(Date().timeIntervalSince1970 * 1000),
            "metadata": meta,
        ]
        body["environment"] = config.environment
        if let r = config.release { body["release"] = r }
        if let b = config.branchName { body["branch_name"] = b }

        let ci = automation.snapshotForEmit()
        post(path: "/rum/session/start", body: body, ciTestInfo: ci)
    }

    private func postEvents(_ events: [BufferedEvent]) {
        for partition in partitionByCiSnapshot(events) {
            let arr: [[String: Any]] = partition.map { e in
                [
                    "title": e.title,
                    "event_index": e.eventIndex,
                    "timestamp_millis": e.timestampMillis,
                    "metadata": e.metadata ?? [:],
                ]
            }
            let body: [String: Any] = [
                "session_id": storedSessionId,
                "events": arr,
            ]
            let ciHeader = partition.first?.ciTestInfoSnapshot
            post(path: "/rum/events", body: body, ciTestInfo: ciHeader)
        }
    }

    private func partitionByCiSnapshot(_ events: [BufferedEvent]) -> [[BufferedEvent]] {
        guard let first = events.first else { return [] }
        var out: [[BufferedEvent]] = []
        var current: [BufferedEvent] = [first]
        var currentCi = first.ciTestInfoSnapshot

        for event in events.dropFirst() {
            if event.ciTestInfoSnapshot == currentCi {
                current.append(event)
            } else {
                out.append(current)
                current = [event]
                currentCi = event.ciTestInfoSnapshot
            }
        }
        out.append(current)
        return out
    }

    private func isTrueCoverageClearURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "testchimp-rum" else { return false }
        guard url.host?.lowercased() == "truecoverage" else { return false }
        return url.path.lowercased() == "/v1/clear"
    }

    private func isTrueCoverageFlushURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "testchimp-rum" else { return false }
        guard url.host?.lowercased() == "truecoverage" else { return false }
        return url.path.lowercased() == "/v1/flush"
    }

    private func post(path: String, body: [String: Any], ciTestInfo: String?) {
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        guard let url = URL(string: baseUrl + path) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(config.projectId, forHTTPHeaderField: "Project-Id")
        req.setValue(config.apiKey, forHTTPHeaderField: "TestChimp-Api-Key")
        if let ci = ciTestInfo, !ci.isEmpty {
            req.setValue(ci, forHTTPHeaderField: "ci-test-info")
        }
        req.setValue(String(TestChimpRum.iosPlatformOrdinal), forHTTPHeaderField: TestChimpRum.rumPlatformHeaderName)
        req.httpBody = data
        URLSession.shared.dataTask(with: req).resume()
    }
}
