import Foundation
import Testing
@testable import DeskBar

@Test
func smClientConfigurationParsesTopLevelAPIURL() {
    let contents = """
    # Shared Session Manager client config
    api_url: "http://primary.example.test:8420/"
    """

    #expect(SMClientConfiguration.apiURL(inConfigContents: contents)?.absoluteString == "http://primary.example.test:8420")
}

@Test
func smClientConfigurationRejectsNonHTTPAPIURL() {
    let contents = """
    api_url: "file:///tmp/sm.sock"
    """

    #expect(SMClientConfiguration.apiURL(inConfigContents: contents) == nil)
}

@Test
func smClientConfigurationUsesEnvironmentBeforeConfigFile() throws {
    let configURL = try temporaryConfigURL(contents: "api_url: http://config.example.test:8420\n")
    defer { try? FileManager.default.removeItem(at: configURL.deletingLastPathComponent()) }

    let resolvedURL = SMClientConfiguration.resolvedAPIBaseURL(environment: [
        "SM_API_URL": "http://env.example.test:8420",
        "SM_CLIENT_CONFIG": configURL.path
    ])

    #expect(resolvedURL.absoluteString == "http://env.example.test:8420")
}

@Test
func smClientConfigurationUsesSharedConfigFile() throws {
    let configURL = try temporaryConfigURL(contents: "api_url: http://config.example.test:8420\n")
    defer { try? FileManager.default.removeItem(at: configURL.deletingLastPathComponent()) }

    let resolvedURL = SMClientConfiguration.resolvedAPIBaseURL(environment: [
        "SM_CLIENT_CONFIG": configURL.path
    ])

    #expect(resolvedURL.absoluteString == "http://config.example.test:8420")
}

@Test
func smClientConfigurationBuildsAPIPathFromResolvedBaseURL() throws {
    let configURL = try temporaryConfigURL(contents: "api_url: http://config.example.test:8420/\n")
    defer { try? FileManager.default.removeItem(at: configURL.deletingLastPathComponent()) }

    let url = SMClientConfiguration.apiURL(path: "/sessions/session-123/kill", environment: [
        "SM_CLIENT_CONFIG": configURL.path
    ])

    #expect(url?.absoluteString == "http://config.example.test:8420/sessions/session-123/kill")
}

private func temporaryConfigURL(contents: String) throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("SMClientConfigurationTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

    let configURL = directoryURL.appendingPathComponent("client.yaml")
    try contents.write(to: configURL, atomically: true, encoding: .utf8)
    return configURL
}
