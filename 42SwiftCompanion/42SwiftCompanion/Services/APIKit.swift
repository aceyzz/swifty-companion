import Foundation

struct Endpoint {
    let path: String
    let queryItems: [URLQueryItem]

    init(path: String, queryItems: [URLQueryItem] = []) {
        self.path = path
        self.queryItems = queryItems
    }

    func urlRequest(token: String) -> URLRequest? {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "api.intra.42.fr"
        comps.path = path
        if !queryItems.isEmpty { comps.queryItems = queryItems }
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return req
    }
}

actor APIClient {
    static let shared = APIClient()
    private let decoder = JSONDecoder()
    private let pageSize = 15

    func request<T: Decodable>(_ endpoint: Endpoint, as type: T.Type) async throws -> T {
        try await requestWithRetry(endpoint, as: type, retriedAfter401: false)
    }

    private func requestWithRetry<T: Decodable>(_ endpoint: Endpoint, as type: T.Type, retriedAfter401: Bool) async throws -> T {
        guard let token = await AuthService.shared.accessToken, !token.isEmpty else { throw URLError(.userAuthenticationRequired) }
        guard let req = endpoint.urlRequest(token: token) else { throw URLError(.badURL) }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        switch http.statusCode {
        case 200...299:
            return try decoder.decode(T.self, from: data)
        case 401 where retriedAfter401 == false:
            await AuthService.shared.refreshAccessToken()
            return try await requestWithRetry(endpoint, as: type, retriedAfter401: true)
        case 429:
            let delayMs = backoffDelayMs(for: http)
            try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
            return try await requestWithRetry(endpoint, as: type, retriedAfter401: retriedAfter401)
        default:
            throw URLError(.badServerResponse)
        }
    }

    private func backoffDelayMs(for http: HTTPURLResponse) -> Int {
        if let retryAfter = http.value(forHTTPHeaderField: "Retry-After"), let sec = Int(retryAfter) { return max(sec * 1000, 500) }
        return 1000
    }

    func pagedRequest<T: Decodable>(_ make: (Int) -> Endpoint, delayNs: UInt64 = 700_000_000) async throws -> [T] {
        var all: [T] = []
        var page = 1
        while true {
            let endpoint = make(page)
            let items: [T] = try await request(endpoint, as: [T].self)
            if items.isEmpty { break }
            all.append(contentsOf: items)
            if items.count < pageSize { break }
            page += 1
            try? await Task.sleep(nanoseconds: delayNs)
        }
        return all
    }
}
