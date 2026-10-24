import Foundation

extension URLSession {
    /// The session for every download and release lookup: it keeps no
    /// cookies or cache, its User-Agent names only Sugu, where URLSession's
    /// own would name the macOS version, and it sends no preferred languages.
    public static let sugu: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpAdditionalHeaders = ["User-Agent": "Sugu", "Accept-Language": "*"]
        return URLSession(configuration: configuration)
    }()
}
