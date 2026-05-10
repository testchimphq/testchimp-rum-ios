import Foundation

/// Plain JSON-serializable metadata values (mirrors @testchimp/rum-js `D()`).
enum RumValidation {
    static let maxMetadataKeys = 10
    static let maxKeyLength = 50
    static let maxStringValueLength = 200
    static let maxMetadataArrayLength = 50
    static let maxTitleLength = 100
    static let maxEventPayloadBytes = 5120

    static func normalizeMetadata(_ raw: [String: Any]?) -> [String: Any]? {
        guard let raw = raw, !raw.isEmpty else { return nil }
        guard raw.count <= maxMetadataKeys else { return nil }
        var out: [String: Any] = [:]
        for (k, v) in raw {
            guard k.count <= maxKeyLength else { return nil }
            if let s = v as? String {
                guard s.count <= maxStringValueLength else { return nil }
                out[k] = s
            } else if let n = v as? NSNumber {
                out[k] = n
            } else if v is Bool {
                out[k] = v
            } else if v is NSNull {
                out[k] = NSNull()
            } else if let arr = v as? [Any] {
                guard arr.count <= maxMetadataArrayLength else { return nil }
                var na: [Any] = []
                for item in arr {
                    if let s = item as? String {
                        guard s.count <= maxStringValueLength else { return nil }
                        na.append(s)
                    } else if let n = item as? NSNumber {
                        na.append(n)
                    } else if item is Bool {
                        na.append(item)
                    } else if item is NSNull {
                        na.append(NSNull())
                    } else {
                        return nil
                    }
                }
                out[k] = na
            } else {
                return nil
            }
        }
        return out.isEmpty ? nil : out
    }

    static func buildEmitPayload(title: String, metadata: [String: Any]?) -> Data? {
        guard !title.isEmpty, title.count <= maxTitleLength else { return nil }
        var obj: [String: Any] = [
            "title": title,
            "timestampMillis": Int64(Date().timeIntervalSince1970 * 1000),
        ]
        if let m = normalizeMetadata(metadata) {
            obj["metadata"] = m
        }
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: []),
              data.count <= maxEventPayloadBytes
        else {
            return nil
        }
        return data
    }
}
