import Foundation

public enum MatchKind: String, Codable, CaseIterable, Sendable {
    case exactHost, domainAndSubdomains, subdomainsOnly, keyword, urlPrefix, wildcard, regex
}

public enum URLPolicy {
    public static func validate(_ text: String) throws -> URL {
        guard text.utf8.count <= 32768, !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let components = URLComponents(string: text), let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty, components.user == nil, components.password == nil,
              let url = components.url else { throw URLError(.badURL) }
        let bytes = Array(text.utf8)
        for i in bytes.indices where bytes[i] == 37 {
            guard i + 2 < bytes.count, bytes[i+1].isHex, bytes[i+2].isHex else { throw URLError(.badURL) }
        }
        return url
    }
    public static func canonicalHost(_ text: String) -> String? {
        guard !text.isEmpty, !text.contains("/"), !text.contains("@"), !text.contains("?"), !text.contains("#"), (!text.contains(":") || (text.hasPrefix("[") && text.hasSuffix("]"))),
              let url = URL(string: "https://\(text)"), let host = url.host else { return nil }
        var result = host.lowercased()
        if result.hasSuffix(".") { result.removeLast() }
        guard !result.isEmpty, !result.contains("..") else { return nil }
        return result
    }
}
private extension UInt8 { var isHex: Bool { (48...57).contains(self) || (65...70).contains(self) || (97...102).contains(self) } }

public enum TypedMatcher {
    public static func matches(kind: MatchKind, value: String, url: URL) -> Bool {
        (try? evaluate(kind: kind, value: value, url: url, compiledRegex: nil)) ?? false
    }
    static func evaluate(kind: MatchKind, value: String, url: URL, compiledRegex: NSRegularExpression?) throws -> Bool {
        guard !value.isEmpty else { return false }
        let host = url.host.flatMap(URLPolicy.canonicalHost)
        let base = URLPolicy.canonicalHost(value)
        switch kind {
        case .exactHost: return host != nil && host == base
        case .domainAndSubdomains: guard let host, let base else { return false }; return host == base || host.hasSuffix("." + base)
        case .subdomainsOnly: guard let host, let base else { return false }; return host != base && host.hasSuffix("." + base)
        case .keyword: return url.absoluteString.range(of: value, options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX")) != nil
        case .urlPrefix: return normalized(url).hasPrefix((try? URLPolicy.validate(value)).map(normalized) ?? "\u{0}")
        case .wildcard: return WildcardPattern(value)?.matches(url) ?? false
        case .regex:
            guard let regex = compiledRegex ?? (try? NSRegularExpression(pattern: value)) else { return false }
            let text = url.absoluteString; let deadline = Date().addingTimeInterval(0.025)
            var found = false
            var timedOut = false
            regex.enumerateMatches(in: text, options: [.reportProgress], range: NSRange(text.startIndex..<text.endIndex, in: text)) { match, _, stop in
                if Date() > deadline { timedOut = true; stop.pointee = true; return }
                if match != nil { found = true; stop.pointee = true }
            }
            if timedOut { throw RegexBudgetExceeded() }
            return found
        }
    }
    private static func normalized(_ url: URL) -> String {
        guard var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.absoluteString }
        c.scheme = c.scheme?.lowercased(); c.host = c.host.flatMap(URLPolicy.canonicalHost)
        return c.string ?? url.absoluteString
    }
}

public enum ProfileDirectory {
    public static func isValid(_ value: String) -> Bool {
        if value == "Default" { return true }
        guard value.hasPrefix("Profile ") else { return false }
        let suffix = value.dropFirst(8)
        return !suffix.isEmpty && suffix.count <= 6 && suffix.first != "0" && suffix.allSatisfy { $0 >= "0" && $0 <= "9" }
    }
}

struct RegexBudgetExceeded: Error {}
