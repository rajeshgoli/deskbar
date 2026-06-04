import Foundation

enum SMClientConfiguration {
    static let defaultAPIBaseURL = URL(string: "http://127.0.0.1:8420")!

    private static let apiURLEnvironmentKey = "SM_API_URL"
    private static let clientConfigEnvironmentKey = "SM_CLIENT_CONFIG"
    private static let xdgConfigHomeEnvironmentKey = "XDG_CONFIG_HOME"
    private static let clientConfigRelativePath = "session-manager/client.yaml"

    static func resolvedAPIBaseURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        if let envURL = normalizedAPIURL(environment[apiURLEnvironmentKey]) {
            return envURL
        }

        let configURL = clientConfigURL(environment: environment, fileManager: fileManager)
        if let configAPIURL = readAPIURL(from: configURL) {
            return configAPIURL
        }

        return defaultAPIBaseURL
    }

    static func apiURL(
        path: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        let baseURL = resolvedAPIBaseURL(environment: environment, fileManager: fileManager)
        let base = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        return URL(string: base + normalizedPath)
    }

    static func readAPIURL(from configURL: URL) -> URL? {
        guard let contents = try? String(contentsOf: configURL, encoding: .utf8) else {
            return nil
        }

        return apiURL(inConfigContents: contents)
    }

    static func apiURL(inConfigContents contents: String) -> URL? {
        for line in contents.components(separatedBy: .newlines) {
            guard let value = configValue(named: "api_url", in: line),
                  let url = normalizedAPIURL(value)
            else {
                continue
            }

            return url
        }

        return nil
    }

    private static func clientConfigURL(
        environment: [String: String],
        fileManager: FileManager
    ) -> URL {
        if let override = nonEmpty(environment[clientConfigEnvironmentKey]) {
            return URL(fileURLWithPath: expandTilde(in: override))
        }

        if let xdgConfigHome = nonEmpty(environment[xdgConfigHomeEnvironmentKey]) {
            return URL(fileURLWithPath: expandTilde(in: xdgConfigHome))
                .appendingPathComponent(clientConfigRelativePath)
        }

        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".config")
            .appendingPathComponent(clientConfigRelativePath)
    }

    private static func configValue(named name: String, in line: String) -> String? {
        let withoutComment = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        let trimmedLine = withoutComment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedLine.hasPrefix("\(name):") else {
            return nil
        }

        let rawValue = trimmedLine.dropFirst(name.count + 1)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripMatchingQuotes(String(rawValue))
    }

    private static func normalizedAPIURL(_ value: String?) -> URL? {
        guard let value = nonEmpty(value) else {
            return nil
        }

        let normalizedValue = value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: normalizedValue),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil
        else {
            return nil
        }

        return url
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedValue, !trimmedValue.isEmpty else {
            return nil
        }

        return trimmedValue
    }

    private static func stripMatchingQuotes(_ value: String) -> String {
        guard value.count >= 2 else {
            return value
        }

        let first = value.first
        let last = value.last
        if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            return String(value.dropFirst().dropLast())
        }

        return value
    }

    private static func expandTilde(in path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}
