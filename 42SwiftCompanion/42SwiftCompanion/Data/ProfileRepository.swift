import Foundation

final class ProfileRepository {
    static let shared = ProfileRepository()
    private let api: APIClient

    init(client: APIClient = .shared) {
        self.api = client
    }

    func basicProfile(login: String) async throws -> UserProfile {
        let user: UserInfoRaw = try await api.request(Endpoint(path: "/v2/users/\(login)"), as: UserInfoRaw.self)
        return UserProfile(raw: user)
    }

    func fetchCoalitions(login: String) async throws -> ([CoalitionRaw], [CoalitionUserRaw]) {
        async let coalitions: [CoalitionRaw] = api.request(Endpoint(path: "/v2/users/\(login)/coalitions"), as: [CoalitionRaw].self)
        async let coalitionUsers: [CoalitionUserRaw] = api.request(Endpoint(path: "/v2/users/\(login)/coalitions_users"), as: [CoalitionUserRaw].self)
        return try await (coalitions, coalitionUsers)
    }

    func fetchProjects(login: String) async throws -> [ProjectRaw] {
        try await api.pagedRequest { page in
            Endpoint(path: "/v2/users/\(login)/projects_users", queryItems: [URLQueryItem(name: "page", value: "\(page)")])
        }
    }

    func assemble(user: UserInfoRaw, coalitions: ([CoalitionRaw], [CoalitionUserRaw]), projects: [ProjectRaw]) -> UserProfile {
        let mergedCoalitions: [UserProfile.Coalition] = coalitions.0.map { c in
            let s = coalitions.1.first { $0.coalition_id == c.id }
            return UserProfile.Coalition(id: c.id, name: c.name, slug: c.slug, color: c.color, imageURL: URL(string: c.image_url), score: s?.score ?? c.score, rank: s?.rank)
        }
        let split = mapProjects(projects)
        return UserProfile(raw: user, coalitions: mergedCoalitions, finishedProjects: split.finished, activeProjects: split.active, currentHost: nil)
    }

    func applyCoalitions(to profile: UserProfile, coalitions: ([CoalitionRaw], [CoalitionUserRaw])) -> UserProfile {
        let merged: [UserProfile.Coalition] = coalitions.0.map { c in
            let s = coalitions.1.first { $0.coalition_id == c.id }
            return UserProfile.Coalition(id: c.id, name: c.name, slug: c.slug, color: c.color, imageURL: URL(string: c.image_url), score: s?.score ?? c.score, rank: s?.rank)
        }
        return profile.with(coalitions: merged)
    }

    func applyProjects(to profile: UserProfile, projects: [ProjectRaw]) -> UserProfile {
        let split = mapProjects(projects)
        return profile.with(projectsFinished: split.finished, projectsActive: split.active)
    }

    func applyCurrentHost(to profile: UserProfile, host: String?) -> UserProfile {
        profile.with(currentHost: host)
    }

    private func mapProjects(_ projects: [ProjectRaw]) -> (finished: [UserProfile.Project], active: [UserProfile.ActiveProject]) {
        let finished: [UserProfile.Project] = projects.filter {
            $0.final_mark != nil && ($0.status == "finished" || $0.status == "waiting_for_correction") && ($0.closed_at != nil || $0.marked_at != nil)
        }.compactMap { p in
            guard let name = p.project.name, let slug = p.project.slug else { return nil }
            return UserProfile.Project(id: slug, name: name, slug: slug, finalMark: p.final_mark, validated: p.validated, closedAt: DateParser.iso(p.closed_at ?? p.marked_at), retry: p.occurrence, cursusId: p.cursus_ids.first, createdAt: DateParser.iso(p.created_at))
        }.sorted { ($0.closedAt ?? .distantPast) > ($1.closedAt ?? .distantPast) }

        let active: [UserProfile.ActiveProject] = projects.filter {
            $0.final_mark == nil && $0.current_team_id != nil && ($0.teams?.isEmpty == false)
        }.compactMap { p in
            guard let name = p.project.name, let slug = p.project.slug else { return nil }
            let team = p.teams?.first
            let repo = team?.repo_url.flatMap { URL(string: $0) }
            return UserProfile.ActiveProject(id: slug, name: name, slug: slug, status: p.status, teamStatus: team?.status, repoURL: repo, registeredAt: DateParser.iso(p.created_at), cursusId: p.cursus_ids.first, retry: p.occurrence, createdAt: DateParser.iso(p.created_at))
        }.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }

        return (finished, active)
    }
}
