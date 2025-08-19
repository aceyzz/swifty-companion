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
        if let retryAfter = http.value(forHTTPHeaderField: "Retry-After"),
           let sec = Int(retryAfter) { return max(sec * 1000, 500) }
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

final class ProfileRepository {
    static let shared = ProfileRepository()
    private let api = APIClient.shared

    func myProfile() async throws -> UserProfile {
        let login = await AuthService.shared.getCurrentUserLogin()
        guard !login.isEmpty else { throw URLError(.userAuthenticationRequired) }
        return try await fullProfile(login: login)
    }

    func fullProfile(login: String) async throws -> UserProfile {
        let user: UserInfoRaw = try await api.request(Endpoint(path: "/v2/users/\(login)"), as: UserInfoRaw.self)
        try? await Task.sleep(nanoseconds: 700_000_000)
        let coalitions: [CoalitionRaw] = try await api.request(Endpoint(path: "/v2/users/\(login)/coalitions"), as: [CoalitionRaw].self)
        try? await Task.sleep(nanoseconds: 700_000_000)
        let coalitionUsers: [CoalitionUserRaw] = try await api.request(Endpoint(path: "/v2/users/\(login)/coalitions_users"), as: [CoalitionUserRaw].self)
        try? await Task.sleep(nanoseconds: 700_000_000)
        let projects: [ProjectRaw] = try await api.pagedRequest { page in
            Endpoint(path: "/v2/users/\(login)/projects_users",
                     queryItems: [URLQueryItem(name: "page", value: "\(page)")])
        }

        let coalitionsMerged: [UserProfile.Coalition] = coalitions.map { c in
            let s = coalitionUsers.first { $0.coalition_id == c.id }
            return UserProfile.Coalition(id: c.id, name: c.name, slug: c.slug, color: c.color, imageURL: URL(string: c.image_url), score: s?.score, rank: s?.rank)
        }

        let finished: [UserProfile.Project] = projects.filter {
            $0.final_mark != nil && ($0.status == "finished" || $0.status == "waiting_for_correction") && ($0.closed_at != nil || $0.marked_at != nil)
        }.compactMap { p in
            guard let name = p.project.name, let slug = p.project.slug else { return nil }
            return UserProfile.Project(id: slug,
                                       name: name,
                                       slug: slug,
                                       finalMark: p.final_mark,
                                       validated: p.validated,
                                       closedAt: DateParser.iso(p.closed_at ?? p.marked_at),
                                       retry: p.occurrence,
                                       cursusId: p.cursus_ids.first,
                                       createdAt: DateParser.iso(p.created_at))
        }.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }

        let active: [UserProfile.ActiveProject] = projects.filter {
            $0.final_mark == nil && $0.current_team_id != nil && ($0.teams?.isEmpty == false)
        }.compactMap { p in
            guard let name = p.project.name, let slug = p.project.slug else { return nil }
            return UserProfile.ActiveProject(id: slug,
                                             name: name,
                                             slug: slug,
                                             status: p.status,
                                             teamStatus: p.teams?.first?.status,
                                             registeredAt: DateParser.iso(p.created_at),
                                             cursusId: p.cursus_ids.first,
                                             retry: p.occurrence,
                                             createdAt: DateParser.iso(p.created_at))
        }.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }

        return UserProfile(raw: user,
                           coalitions: coalitionsMerged,
                           finishedProjects: finished,
                           activeProjects: active,
                           currentHost: nil)
    }
}
