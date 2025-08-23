import Foundation

final class SearchRepository {
    static let shared = SearchRepository()
    private let api = APIClient.shared

    func searchUsers(query: String, limit: Int = 15) async throws -> [UserSummary] {
        guard query.count >= 2 else { return [] }
        let items = [
            URLQueryItem(name: "page[size]", value: "\(limit)"),
            URLQueryItem(name: "search[login]", value: query)
        ]
        let endpoint = Endpoint(path: "/v2/users", queryItems: items)
        let raw: [UserSummaryRaw] = try await api.request(endpoint, as: [UserSummaryRaw].self)
        return raw.map(UserSummary.fromRaw)
    }
}
