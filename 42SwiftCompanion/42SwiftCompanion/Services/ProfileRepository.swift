import Foundation

final class ProfileRepository {
    static let shared = ProfileRepository()
    private let api = APIClient.shared

    func basicProfile(login: String) async throws -> UserProfile {
        let user: UserInfoRaw = try await api.request(Endpoint(path: "/v2/users/\(login)"), as: UserInfoRaw.self)
        return UserProfile(raw: user, coalitions: [], finishedProjects: [], activeProjects: [], currentHost: nil)
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
            return UserProfile.Coalition(id: c.id, name: c.name, slug: c.slug, color: c.color, imageURL: URL(string: c.image_url), score: s?.score, rank: s?.rank)
        }
        let finished: [UserProfile.Project] = projects.filter {
            $0.final_mark != nil && ($0.status == "finished" || $0.status == "waiting_for_correction") && ($0.closed_at != nil || $0.marked_at != nil)
        }.compactMap { p in
            guard let name = p.project.name, let slug = p.project.slug else { return nil }
            return UserProfile.Project(id: slug, name: name, slug: slug, finalMark: p.final_mark, validated: p.validated, closedAt: DateParser.iso(p.closed_at ?? p.marked_at), retry: p.occurrence, cursusId: p.cursus_ids.first, createdAt: DateParser.iso(p.created_at))
        }.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        let active: [UserProfile.ActiveProject] = projects.filter {
            $0.final_mark == nil && $0.current_team_id != nil && ($0.teams?.isEmpty == false)
        }.compactMap { p in
            guard let name = p.project.name, let slug = p.project.slug else { return nil }
            return UserProfile.ActiveProject(id: slug, name: name, slug: slug, status: p.status, teamStatus: p.teams?.first?.status, registeredAt: DateParser.iso(p.created_at), cursusId: p.cursus_ids.first, retry: p.occurrence, createdAt: DateParser.iso(p.created_at))
        }.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        return UserProfile(raw: user, coalitions: mergedCoalitions, finishedProjects: finished, activeProjects: active, currentHost: nil)
    }

    func applyCoalitions(to profile: UserProfile, coalitions: ([CoalitionRaw], [CoalitionUserRaw])) -> UserProfile {
        let merged: [UserProfile.Coalition] = coalitions.0.map { c in
            let s = coalitions.1.first { $0.coalition_id == c.id }
            return UserProfile.Coalition(id: c.id, name: c.name, slug: c.slug, color: c.color, imageURL: URL(string: c.image_url), score: s?.score, rank: s?.rank)
        }
        return UserProfile(id: profile.id, login: profile.login, displayName: profile.displayName, wallet: profile.wallet, correctionPoint: profile.correctionPoint, imageURL: profile.imageURL, poolMonth: profile.poolMonth, poolYear: profile.poolYear, campusName: profile.campusName, userKind: profile.userKind, isActive: profile.isActive, email: profile.email, phone: profile.phone, userNameWithTitle: profile.userNameWithTitle, currentHost: profile.currentHost, cursus: profile.cursus, coalitions: merged, achievements: profile.achievements, finishedProjects: profile.finishedProjects, activeProjects: profile.activeProjects)
    }

    func applyProjects(to profile: UserProfile, projects: [ProjectRaw]) -> UserProfile {
        let finished: [UserProfile.Project] = projects.filter {
            $0.final_mark != nil && ($0.status == "finished" || $0.status == "waiting_for_correction") && ($0.closed_at != nil || $0.marked_at != nil)
        }.compactMap { p in
            guard let name = p.project.name, let slug = p.project.slug else { return nil }
            return UserProfile.Project(id: slug, name: name, slug: slug, finalMark: p.final_mark, validated: p.validated, closedAt: DateParser.iso(p.closed_at ?? p.marked_at), retry: p.occurrence, cursusId: p.cursus_ids.first, createdAt: DateParser.iso(p.created_at))
        }.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        let active: [UserProfile.ActiveProject] = projects.filter {
            $0.final_mark == nil && $0.current_team_id != nil && ($0.teams?.isEmpty == false)
        }.compactMap { p in
            guard let name = p.project.name, let slug = p.project.slug else { return nil }
            return UserProfile.ActiveProject(id: slug, name: name, slug: slug, status: p.status, teamStatus: p.teams?.first?.status, registeredAt: DateParser.iso(p.created_at), cursusId: p.cursus_ids.first, retry: p.occurrence, createdAt: DateParser.iso(p.created_at))
        }.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        return UserProfile(id: profile.id, login: profile.login, displayName: profile.displayName, wallet: profile.wallet, correctionPoint: profile.correctionPoint, imageURL: profile.imageURL, poolMonth: profile.poolMonth, poolYear: profile.poolYear, campusName: profile.campusName, userKind: profile.userKind, isActive: profile.isActive, email: profile.email, phone: profile.phone, userNameWithTitle: profile.userNameWithTitle, currentHost: profile.currentHost, cursus: profile.cursus, coalitions: profile.coalitions, achievements: profile.achievements, finishedProjects: finished, activeProjects: active)
    }

    func applyCurrentHost(to profile: UserProfile, host: String?) -> UserProfile {
        UserProfile(id: profile.id, login: profile.login, displayName: profile.displayName, wallet: profile.wallet, correctionPoint: profile.correctionPoint, imageURL: profile.imageURL, poolMonth: profile.poolMonth, poolYear: profile.poolYear, campusName: profile.campusName, userKind: profile.userKind, isActive: profile.isActive, email: profile.email, phone: profile.phone, userNameWithTitle: profile.userNameWithTitle, currentHost: host, cursus: profile.cursus, coalitions: profile.coalitions, achievements: profile.achievements, finishedProjects: profile.finishedProjects, activeProjects: profile.activeProjects)
    }
}
