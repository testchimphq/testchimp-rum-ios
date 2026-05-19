import Foundation
import XCTest
@testable import TestChimpRum

final class AutomationSessionTests: XCTestCase {
    private let sessionIdKey = "testchimp_session_id"
    private let lastActivityKey = "testchimp_last_activity"

    override func tearDown() {
        TestChimpRum.resetSession()
        let d = UserDefaults.standard
        d.removeObject(forKey: sessionIdKey)
        d.removeObject(forKey: lastActivityKey)
        d.removeObject(forKey: "testchimp_event_count")
        d.removeObject(forKey: "testchimp_event_type_counts")
        d.removeObject(forKey: "testchimp_session_metadata")
        super.tearDown()
    }

    func testFirstSetWithEmptyCiStartsNewSession() throws {
        let oldId = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
        let now = Double(Int64(Date().timeIntervalSince1970 * 1000))
        UserDefaults.standard.set(oldId, forKey: sessionIdKey)
        UserDefaults.standard.set(now, forKey: lastActivityKey)

        TestChimpRum.initialize(
            TestChimpRumConfig(
                projectId: "proj",
                apiKey: "key",
                environment: "staging",
                release: "1.0.0"
            )
        )
        XCTAssertEqual(TestChimpRum.getSessionId(), oldId)
        XCTAssertFalse(TestChimpRum.hasCiTestInfo())

        let setUrl = try makeSetURL(ci: ["testName": "first"])
        XCTAssertTrue(TestChimpRum.handleAutomationURL(setUrl))
        XCTAssertNotEqual(TestChimpRum.getSessionId(), oldId)
        XCTAssertTrue(TestChimpRum.hasCiTestInfo())
    }

    func testSecondSetInSameProcessKeepsSessionId() throws {
        TestChimpRum.initialize(
            TestChimpRumConfig(projectId: "proj", apiKey: "key", environment: "staging")
        )
        let first = try makeSetURL(ci: ["testName": "a"])
        XCTAssertTrue(TestChimpRum.handleAutomationURL(first))
        let afterFirst = TestChimpRum.getSessionId()

        let second = try makeSetURL(ci: ["testName": "b"])
        XCTAssertTrue(TestChimpRum.handleAutomationURL(second))
        XCTAssertEqual(TestChimpRum.getSessionId(), afterFirst)
    }

    func testSessionStoreAssignNewSession() {
        let suite = "io.testchimp.rum.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = SessionStore(defaults: defaults)
        let a = store.assignNewSession(metadata: ["k": "v"])
        let b = store.assignNewSession(metadata: nil)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(defaults.string(forKey: sessionIdKey), b)
    }

    func testAutomationContextHasActiveCiRespectsTtl() {
        let ctx = AutomationContext()
        ctx.ttlSeconds = 0.01
        ctx.setCiTestInfoJson("{\"t\":1}")
        XCTAssertTrue(ctx.hasActiveCiTestInfo())
        Thread.sleep(forTimeInterval: 0.02)
        XCTAssertFalse(ctx.hasActiveCiTestInfo())
    }

    private func makeSetURL(ci: [String: Any]) throws -> URL {
        let data = try JSONSerialization.data(withJSONObject: ci)
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let str = "testchimp-rum://truecoverage/v1/set?p=\(encoded)"
        return try XCTUnwrap(URL(string: str))
    }
}
