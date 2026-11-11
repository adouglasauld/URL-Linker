import Foundation

/// Extracts a routing hint only. The browser must still receive the protected URL.
public enum SafeLinks {
    private static let hostSuffix = "safelinks.protection.outlook.com"
    private static let maximumDepth = 4

    /// Ordinary URLs pass through; malformed or excessively nested wrappers return nil.
    /// No network access, redirects, or repeated percent-decoding is performed.
    public static func matchingURL(for original: URL) -> URL? {
        var current = original
        for _ in 0..<maximumDepth {
            guard isWrapper(current) else { return current }
            guard let validated = try? URLPolicy.validate(current.absoluteString),
                  let components = URLComponents(url: validated, resolvingAgainstBaseURL: false),
                  components.scheme?.lowercased() == "https",
                  components.port == nil || components.port == 443,
                  components.path.isEmpty || components.path == "/",
                  let parameters = components.queryItems else { return nil }
            let destinations = parameters.filter { $0.name == "url" }
            // URLComponents decodes this one query layer. Never decode the result again.
            guard destinations.count == 1, let value = destinations[0].value,
                  let destination = try? URLPolicy.validate(value) else { return nil }
            current = destination
        }
        return isWrapper(current) ? nil : current
    }

    private static func isWrapper(_ url: URL) -> Bool {
        guard let host = url.host.flatMap(URLPolicy.canonicalHost) else { return false }
        return host == hostSuffix || host.hasSuffix("." + hostSuffix)
    }
}
