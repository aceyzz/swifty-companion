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
        comps.path = path.hasPrefix("/") ? path : "/\(path)"
        if !queryItems.isEmpty { comps.queryItems = queryItems }
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return req
    }
}

enum APIError: Error {
    case unauthorized
    case rateLimited(retryAfter: Int?)
    case http(status: Int, body: String?)
    case decoding(Error)
    case transport(URLError)
}

actor APIClient {
    static let shared = APIClient()
    private let decoder = JSONDecoder()

    func request<T: Decodable>(_ endpoint: Endpoint, as type: T.Type) async throws -> T {
        let (data, _) = try await send(endpoint, retriedAfter401: false)
        do { return try decoder.decode(T.self, from: data) }
        catch { throw APIError.decoding(error) }
    }

    func pagedRequest<T: Decodable>(_ make: (Int) -> Endpoint, delayNs: UInt64 = 700_000_000) async throws -> [T] {
        var all: [T] = []
        var page = 1
        while true {
            let endpoint = make(page)
            let (data, response) = try await send(endpoint, retriedAfter401: false)
            let items: [T]
            do { items = try decoder.decode([T].self, from: data) }
            catch { throw APIError.decoding(error) }
            if items.isEmpty { break }
            all.append(contentsOf: items)
            if !hasNextPage(response) { break }
            page += 1
            try? await Task.sleep(nanoseconds: delayNs)
        }
        return all
    }

    private func send(_ endpoint: Endpoint, retriedAfter401: Bool) async throws -> (Data, HTTPURLResponse) {
        guard let token = await AuthService.shared.accessToken, !token.isEmpty else { throw APIError.unauthorized }
        guard let req = endpoint.urlRequest(token: token) else { throw APIError.http(status: 0, body: "Bad URL") }
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw APIError.http(status: 0, body: "No HTTP") }
            switch http.statusCode {
            case 200...299:
                return (data, http)
            case 401 where !retriedAfter401:
                await AuthService.shared.refreshAccessToken()
                return try await send(endpoint, retriedAfter401: true)
            case 429:
                let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
                let delayMs = max((retry ?? 1) * 1000, 500)
                try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
                return try await send(endpoint, retriedAfter401: retriedAfter401)
            default:
                let text = String(data: data, encoding: .utf8)
                throw APIError.http(status: http.statusCode, body: text)
            }
        } catch let e as URLError {
            throw APIError.transport(e)
        }
    }

    private func hasNextPage(_ http: HTTPURLResponse) -> Bool {
        guard let link = http.value(forHTTPHeaderField: "Link") else { return false }
        return link.split(separator: ",").contains { $0.range(of: "rel=\"next\"") != nil }
    }
}
