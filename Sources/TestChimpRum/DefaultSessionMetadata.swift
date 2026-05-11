import Darwin
import Foundation
#if os(iOS)
import UIKit
#endif

/// Client-derived session init metadata (mirrors @testchimp/rum-js defaults + mobile fields).
enum DefaultSessionMetadata {
    private static let maxStringLen = 200

    private static func truncate(_ s: String) -> String {
        if s.count <= maxStringLen { return s }
        return String(s.prefix(maxStringLen))
    }

    /// Hardware model id (e.g. `iPhone15,2`, `Mac14,2`) when available.
    private static func hardwareMachineName() -> String? {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        guard size > 1 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.machine", &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }

    #if os(iOS)
    private static func deviceTypeIOS() -> String {
        switch UIDevice.current.userInterfaceIdiom {
        case .pad: return "tablet"
        case .phone: return "mobile"
        case .mac: return "desktop"
        case .tv: return "tv"
        case .carPlay: return "mobile"
        case .vision: return "mobile"
        @unknown default: return "mobile"
        }
    }
    #endif

    static func dictionaryForSessionStart() -> [String: Any] {
        var m: [String: Any] = [
            "_language": truncate(Locale.current.identifier),
            "_timezone": truncate(TimeZone.current.identifier),
            "_manufacturer": "Apple",
        ]
        #if os(iOS)
        m["_platform"] = "ios"
        m["_os"] = "ios"
        m["_device_type"] = deviceTypeIOS()
        m["_os_version"] = truncate(UIDevice.current.systemVersion)
        if let hw = hardwareMachineName() {
            m["_device_model"] = truncate(hw)
        } else {
            m["_device_model"] = truncate(UIDevice.current.model)
        }
        #elseif os(macOS)
        m["_platform"] = "macos"
        m["_os"] = "mac"
        m["_device_type"] = "desktop"
        let v = ProcessInfo.processInfo.operatingSystemVersion
        m["_os_version"] = truncate("\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)")
        if let hw = hardwareMachineName() {
            m["_device_model"] = truncate(hw)
        } else {
            m["_device_model"] = "Mac"
        }
        #endif
        return m
    }
}
