import Foundation

struct Endpoint {
    enum HTTPMethod: String { case get = "GET", post = "POST", patch = "PATCH", delete = "DELETE" }

    let path: String
    let queryItems: [URLQueryItem]
    var method: HTTPMethod
    var headers: [String: String]
    var body: Data?

    init(path: String,
         queryItems: [URLQueryItem] = [],
         method: HTTPMethod = .get,
         headers: [String: String] = [:],
         body: Data? = nil) {
        self.path = path
        self.queryItems = queryItems
        self.method = method
        self.headers = headers
        self.body = body
    }

    func urlRequest(token: String) -> URLRequest? {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "api.intra.42.fr"
        comps.path = path.hasPrefix("/") ? path : "/\(path)"
        if !queryItems.isEmpty { comps.queryItems = queryItems }
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = method.rawValue
        req.httpBody = body
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        headers.forEach { k, v in req.setValue(v, forHTTPHeaderField: k) }
        req.timeoutInterval = 30
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
    private let session: URLSession
    private let maxAttempts = 3

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 60
        cfg.waitsForConnectivity = true
        cfg.allowsExpensiveNetworkAccess = true
        cfg.allowsConstrainedNetworkAccess = true
        cfg.httpAdditionalHeaders = ["Accept": "application/json"]
        session = URLSession(configuration: cfg)
    }

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
        guard let baseReq = endpoint.urlRequest(token: token) else { throw APIError.http(status: 0, body: "Bad URL") }
        var attempt = 0
        while true {
            try Task.checkCancellation()
            var req = baseReq
            req.networkServiceType = .responsiveData
            do {
                let (data, response) = try await session.data(for: req)
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
                case 500...599:
                    attempt += 1
                    if attempt >= maxAttempts { throw APIError.http(status: http.statusCode, body: String(data: data, encoding: .utf8)) }
                    try? await Task.sleep(nanoseconds: backoffDelay(attempt: attempt))
                default:
                    let text = String(data: data, encoding: .utf8)
                    throw APIError.http(status: http.statusCode, body: text)
                }
            } catch let e as URLError {
                attempt += 1
                if attempt >= maxAttempts { throw APIError.transport(e) }
                if shouldRetry(error: e) {
                    try? await Task.sleep(nanoseconds: backoffDelay(attempt: attempt))
                } else {
                    throw APIError.transport(e)
                }
            }
        }
    }

    private func hasNextPage(_ http: HTTPURLResponse) -> Bool {
        guard let link = http.value(forHTTPHeaderField: "Link") else { return false }
        return link.split(separator: ",").contains { $0.range(of: "rel=\"next\"") != nil }
    }

    private func shouldRetry(error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .dnsLookupFailed, .notConnectedToInternet, .resourceUnavailable, .internationalRoamingOff, .callIsActive, .dataNotAllowed:
            return true
        default:
            return false
        }
    }

    private func backoffDelay(attempt: Int) -> UInt64 {
        let base: Double = 0.8
        let jitter = Double.random(in: 0...0.4)
        let seconds = pow(2, Double(attempt - 1)) * base * (1 + jitter)
        return UInt64(seconds * 1_000_000_000)
    }
}
