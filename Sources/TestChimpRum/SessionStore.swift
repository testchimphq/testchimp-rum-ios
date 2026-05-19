import Foundation
import Security

/// UserDefaults-backed session (mirrors rum-js localStorage keys).
final class SessionStore {
    private let defaults: UserDefaults
    private let sessionIdKey = "testchimp_session_id"
    private let lastActivityKey = "testchimp_last_activity"
    private let eventCountKey = "testchimp_event_count"
    private let eventTypeCountsKey = "testchimp_event_type_counts"
    private let sessionMetadataKey = "testchimp_session_metadata"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadOrCreateSessionId(proposed: String?, sessionMetadata: [String: Any]?, inactivityMs: Int64) -> (id: String, isNew: Bool) {
        if let p = proposed, !p.isEmpty {
            persistSession(id: p, metadata: sessionMetadata)
            return (p, false)
        }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        if let sid = defaults.string(forKey: sessionIdKey) {
            let lastMs = Int64(defaults.double(forKey: lastActivityKey))
            if lastMs > 0, nowMs - lastMs < inactivityMs {
                touchActivity()
                return (sid, false)
            }
        }
        let id = SessionStore.newSessionId()
        persistSession(id: id, metadata: sessionMetadata)
        return (id, true)
    }

    func touchActivity() {
        let now = Double(Int64(Date().timeIntervalSince1970 * 1000))
        defaults.set(now, forKey: lastActivityKey)
    }

    func eventCount() -> Int {
        defaults.integer(forKey: eventCountKey)
    }

    func setEventCount(_ n: Int) {
        defaults.set(n, forKey: eventCountKey)
    }

    func eventTypeCounts() -> [String: Int] {
        guard let data = defaults.data(forKey: eventTypeCountsKey),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Int]
        else {
            return [:]
        }
        return obj
    }

    func setEventTypeCounts(_ c: [String: Int]) {
        if let data = try? JSONSerialization.data(withJSONObject: c) {
            defaults.set(data, forKey: eventTypeCountsKey)
        }
    }

    func sessionMetadata() -> [String: Any]? {
        guard let s = defaults.string(forKey: sessionMetadataKey),
              let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return obj
    }

    func clearAll() {
        defaults.removeObject(forKey: sessionIdKey)
        defaults.removeObject(forKey: lastActivityKey)
        defaults.removeObject(forKey: eventCountKey)
        defaults.removeObject(forKey: eventTypeCountsKey)
        defaults.removeObject(forKey: sessionMetadataKey)
    }

    /// Replaces any persisted session with a new id and zeroed counters (automation per-test boundary).
    func assignNewSession(metadata: [String: Any]?) -> String {
        let id = SessionStore.newSessionId()
        persistSession(id: id, metadata: metadata)
        return id
    }

    private func persistSession(id: String, metadata: [String: Any]?) {
        let now = Double(Int64(Date().timeIntervalSince1970 * 1000))
        defaults.set(id, forKey: sessionIdKey)
        defaults.set(now, forKey: lastActivityKey)
        defaults.set(0, forKey: eventCountKey)
        if let data = try? JSONSerialization.data(withJSONObject: [String: Int]()) {
            defaults.set(data, forKey: eventTypeCountsKey)
        }
        if let m = metadata,
           let data = try? JSONSerialization.data(withJSONObject: m),
           let json = String(data: data, encoding: .utf8)
        {
            defaults.set(json, forKey: sessionMetadataKey)
        } else {
            defaults.removeObject(forKey: sessionMetadataKey)
        }
    }

    private static let crockford: [Character] = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    private static func newSessionId() -> String {
        var t = UInt64(Date().timeIntervalSince1970 * 1000)
        var timePart = ""
        for _ in 0 ..< 10 {
            timePart = String(crockford[Int(t % 32)]) + timePart
            t /= 32
        }
        var rnd = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, rnd.count, &rnd)
        var randPart = ""
        for b in rnd {
            randPart.append(crockford[Int(b % 32)])
        }
        return timePart + randPart
    }
}
