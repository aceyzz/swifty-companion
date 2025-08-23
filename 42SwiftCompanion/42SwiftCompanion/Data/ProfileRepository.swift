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
        let mergedCoalitions = mergeCoalitions(coalitions.0, coalitions.1)
        let split = mapProjects(projects)
        return UserProfile(raw: user, coalitions: mergedCoalitions, finishedProjects: split.finished, activeProjects: split.active, currentHost: nil)
    }

    func applyCoalitions(to profile: UserProfile, coalitions: ([CoalitionRaw], [CoalitionUserRaw])) -> UserProfile {
        let merged = mergeCoalitions(coalitions.0, coalitions.1)
        return profile.with(coalitions: merged)
    }

    func applyProjects(to profile: UserProfile, projects: [ProjectRaw]) -> UserProfile {
        let split = mapProjects(projects)
        return profile.with(projectsFinished: split.finished, projectsActive: split.active)
    }

    func applyCurrentHost(to profile: UserProfile, host: String?) -> UserProfile {
        profile.with(currentHost: host)
    }

    private func mergeCoalitions(_ coalitions: [CoalitionRaw], _ users: [CoalitionUserRaw]) -> [UserProfile.Coalition] {
        coalitions.map { c in
            let s = users.first { $0.coalition_id == c.id }
            return UserProfile.Coalition(id: c.id, name: c.name, slug: c.slug, color: c.color, imageURL: URL(string: c.image_url), score: s?.score ?? c.score, rank: s?.rank)
        }
    }

    private func mapProjects(_ projects: [ProjectRaw]) -> (finished: [UserProfile.Project], active: [UserProfile.ActiveProject]) {
        struct Norm {
            let slug: String
            let name: String
            let cursusId: Int?
            let retry: Int?
            let repoURL: URL?
            let status: String?
            let teamStatus: String?
            let registeredAt: Date?
            let endAt: Date?
            let finalMark: Int?
            let validated: Bool?
        }

        let normalized: [Norm] = projects.compactMap { p in
            guard let name = p.project.name, let slug = p.project.slug else { return nil }
            let teamById = { (id: Int?) -> TeamRaw? in
                guard let id else { return nil }
                return p.teams?.first(where: { $0.id == id })
            }(p.current_team_id)

            let finishedDates: [Date] = [
                DateParser.iso(p.closed_at),
                DateParser.iso(p.marked_at)
            ].compactMap { $0 } + (p.teams?.compactMap { DateParser.iso($0.closed_at) } ?? [])

            let endAt = finishedDates.max()
            let repo = (teamById?.repo_url ?? p.teams?.first?.repo_url).flatMap(URL.init(string:))
            return Norm(
                slug: slug,
                name: name,
                cursusId: p.cursus_ids.first,
                retry: p.occurrence,
                repoURL: repo,
                status: p.status,
                teamStatus: teamById?.status ?? p.teams?.first?.status,
                registeredAt: DateParser.iso(p.created_at),
                endAt: endAt,
                finalMark: p.final_mark,
                validated: p.validated
            )
        }

        let finished: [UserProfile.Project] = normalized
            .filter { n in
                let st = n.status?.lowercased() ?? ""
                let ts = n.teamStatus?.lowercased() ?? ""
                if n.finalMark != nil { return true }
                if ["finished", "waiting_for_correction"].contains(st) { return true }
                if ["finished", "closed"].contains(ts) { return true }
                if n.endAt != nil { return true }
                return false
            }
            .map { n in
                UserProfile.Project(
                    id: n.slug,
                    name: n.name,
                    slug: n.slug,
                    finalMark: n.finalMark,
                    validated: n.validated,
                    closedAt: n.endAt,
                    retry: n.retry,
                    cursusId: n.cursusId,
                    createdAt: n.registeredAt
                )
            }
            .sorted { ($0.closedAt ?? .distantPast) > ($1.closedAt ?? .distantPast) }

        let active: [UserProfile.ActiveProject] = normalized
            .filter { n in
                let st = n.status?.lowercased() ?? ""
                let ts = n.teamStatus?.lowercased() ?? ""
                let isFinished = (n.finalMark != nil) || ["finished", "waiting_for_correction"].contains(st) || ["finished", "closed"].contains(ts) || (n.endAt != nil)
                return !isFinished
            }
            .map { n in
                UserProfile.ActiveProject(
                    id: n.slug,
                    name: n.name,
                    slug: n.slug,
                    status: n.status,
                    teamStatus: n.teamStatus,
                    repoURL: n.repoURL,
                    registeredAt: n.registeredAt,
                    cursusId: n.cursusId,
                    retry: n.retry,
                    createdAt: n.registeredAt
                )
            }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }

        return (finished, active)
    }
}
