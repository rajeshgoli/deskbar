import Foundation

/// SM endpoints are live local state, not cacheable documents. An ephemeral
/// session avoids persistent CacheDB writes and their recurring sleep assertions.
enum SMHTTPClient {
    static let session = URLSession(configuration: configuration())

    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return configuration
    }
}
