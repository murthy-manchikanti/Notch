import Foundation

struct ReleaseUpdate: Decodable {
    let version: String
    let page: URL

    enum CodingKeys: String, CodingKey {
        case version = "tag_name"
        case page = "html_url"
    }

    static func latest() async throws -> ReleaseUpdate? {
        let endpoint = URL(string: "https://api.github.com/repos/murthy-manchikanti/Notch/releases/latest")!
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: return try JSONDecoder().decode(Self.self, from: data)
        case 404: return nil
        default: throw URLError(.badServerResponse)
        }
    }

    static func isNewer(_ release: String, than installed: String) -> Bool? {
        func components(_ version: String) -> [Int]? {
            let normalized = version.hasPrefix("v") ? String(version.dropFirst()) : version
            let fields = normalized.split(separator: ".", omittingEmptySubsequences: false)
            let values = fields.compactMap { Int($0) }
            guard values.count == fields.count, !values.isEmpty, values.allSatisfy({ $0 >= 0 }) else { return nil }
            return values
        }

        guard let latest = components(release), let current = components(installed) else { return nil }
        for index in 0..<max(latest.count, current.count) {
            let remote = index < latest.count ? latest[index] : 0
            let local = index < current.count ? current[index] : 0
            if remote != local { return remote > local }
        }
        return false
    }
}
