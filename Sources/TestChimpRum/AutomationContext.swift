import Foundation

/// In-process CI / automation metadata for the `ci-test-info` header (TrueCoverage).
final class AutomationContext {
    private let lock = NSLock()
    private var ciTestInfoJson: String?
    private var updatedAt: TimeInterval = 0

    /// Seconds after which automation context is ignored (stale suite / leaked state).
    var ttlSeconds: TimeInterval = 900

    func setCiTestInfoJson(_ json: String) {
        lock.lock()
        defer { lock.unlock() }
        ciTestInfoJson = json
        updatedAt = Date().timeIntervalSince1970
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        ciTestInfoJson = nil
    }

    /// Same eligibility as `snapshotForEmit()` without returning the JSON string.
    func hasActiveCiTestInfo() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let j = ciTestInfoJson, !j.isEmpty else { return false }
        let now = Date().timeIntervalSince1970
        if now - updatedAt > ttlSeconds {
            ciTestInfoJson = nil
            return false
        }
        return true
    }

    /// Snapshot for an `emit()` call (copy at enqueue time).
    func snapshotForEmit() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let j = ciTestInfoJson else { return nil }
        let now = Date().timeIntervalSince1970
        if now - updatedAt > ttlSeconds {
            ciTestInfoJson = nil
            return nil
        }
        return j
    }
}
