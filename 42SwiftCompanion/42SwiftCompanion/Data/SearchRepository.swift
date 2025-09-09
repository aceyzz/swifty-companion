import Foundation

final class SearchRepository {
    static let shared = SearchRepository()
    private let api = APIClient.shared
    private let cache = NetworkCache.shared

    func searchUsers(query: String, limit: Int = 15) async throws -> [UserSummary] {
        guard query.count >= 2 else { return [] }
        
        let cacheKey = await cache.cacheKey(for: "/v2/users/search", params: ["query": query, "limit": "\(limit)"])
        
        if let cached = await cache.get([UserSummary].self, forKey: cacheKey) {
            return cached
        }
        
        let items = [
            URLQueryItem(name: "page[size]", value: "\(limit)"),
            URLQueryItem(name: "search[login]", value: query)
        ]
        let endpoint = Endpoint(path: "/v2/users", queryItems: items)
        let raw: [UserSummaryRaw] = try await api.request(endpoint, as: [UserSummaryRaw].self)
        let result = raw.map(UserSummary.fromRaw)
        
        await cache.set(result, forKey: cacheKey, ttl: 120)
        return result
    }
}
