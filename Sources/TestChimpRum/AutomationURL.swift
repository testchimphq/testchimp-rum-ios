import Foundation

enum AutomationURL {
    /// `testchimp-rum://truecoverage/v1/set?p=<base64url>` and `.../v1/clear`
    static func handle(_ url: URL, context: AutomationContext) -> Bool {
        guard url.scheme?.lowercased() == "testchimp-rum" else { return false }
        guard url.host?.lowercased() == "truecoverage" else { return false }

        let path = url.path.lowercased()
        if path == "/v1/clear" {
            context.clear()
            return true
        }
        if path == "/v1/set" {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let item = components.queryItems?.first(where: { $0.name == "p" }),
                  let encoded = item.value,
                  let data = decodeBase64Url(encoded),
                  let json = String(data: data, encoding: .utf8),
                  !json.isEmpty
            else {
                return false
            }
            context.setCiTestInfoJson(json)
            return true
        }
        return false
    }

    private static func decodeBase64Url(_ s: String) -> Data? {
        var str = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let pad = (4 - str.count % 4) % 4
        if pad > 0 {
            str.append(String(repeating: "=", count: pad))
        }
        return Data(base64Encoded: str)
    }
}
