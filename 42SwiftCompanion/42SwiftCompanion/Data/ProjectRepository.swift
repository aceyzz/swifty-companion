import Foundation

struct ProjectDetails: Equatable {
    let description: String?
    let url: URL?
}

private struct ProjectDetailsRaw: Decodable {
    let id: Int?
    let name: String?
    let slug: String?
    let description: String?
    let url: String?
}

private actor ProjectDetailsCache {
    private var storage: [String: ProjectDetails] = [:]
    func get(for slug: String) -> ProjectDetails? { storage[slug] }
    func set(_ details: ProjectDetails, for slug: String) { storage[slug] = details }
}

final class ProjectDetailsRepository {
    static let shared = ProjectDetailsRepository()
    private let api = APIClient.shared
    private let cache = ProjectDetailsCache()

    func details(for slug: String) async -> ProjectDetails? {
        if let cached = await cache.get(for: slug) { return cached }
        let items: [ProjectDetailsRaw]
        do {
            items = try await api.request(
                Endpoint(
                    path: "/v2/projects",
                    queryItems: [
                        URLQueryItem(name: "filter[slug]", value: slug),
                        URLQueryItem(name: "page[size]", value: "1")
                    ]
                ),
                as: [ProjectDetailsRaw].self
            )
        } catch {
            return nil
        }
        guard let first = items.first else { return nil }
        let fallback = first.slug.flatMap { URL(string: "https://projects.intra.42.fr/projects/\($0)") }
        let details = ProjectDetails(description: first.description, url: first.url.flatMap(URL.init(string:)) ?? fallback)
        await cache.set(details, for: slug)
        return details
    }
}
