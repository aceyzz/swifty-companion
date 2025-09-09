import Foundation

struct CachedCompleteProfile: Codable {
    let profile: UserProfile
    let coalitions: [CoalitionRaw]
    let coalitionUsers: [CoalitionUserRaw]
    let projects: [ProjectRaw]
}

final class ProfileRepository {
    static let shared = ProfileRepository()
    private let api: APIClient
    private let cache = NetworkCache.shared

    init(client: APIClient = .shared) {
        self.api = client
    }

    func basicProfile(login: String) async throws -> UserProfile {
        let cacheKey = await cache.cacheKey(for: "/v2/users/\(login)")
        
        if let cached = await cache.get(UserProfile.self, forKey: cacheKey) {
            return cached
        }
        
        let raw: UserInfoRaw = try await api.request(Endpoint(path: "/v2/users/\(login)"), as: UserInfoRaw.self)
        let profile = UserProfile(raw: raw, coalitions: [], finishedProjects: [], activeProjects: [], currentHost: nil)
        
        await cache.set(profile, forKey: cacheKey, ttl: 900)
        return profile
    }

    func fetchCoalitions(login: String) async throws -> ([CoalitionRaw], [CoalitionUserRaw]) {
        let coalitionsKey = await cache.cacheKey(for: "/v2/users/\(login)/coalitions")
        let usersKey = await cache.cacheKey(for: "/v2/users/\(login)/coalitions_users")
        
        async let cachedCoalitions = cache.get([CoalitionRaw].self, forKey: coalitionsKey)
        async let cachedUsers = cache.get([CoalitionUserRaw].self, forKey: usersKey)
        
        let (coalitions, users) = await (cachedCoalitions, cachedUsers)
        
        if let coalitions, let users {
            return (coalitions, users)
        }
        
        async let coalitionsResult: [CoalitionRaw] = api.request(Endpoint(path: "/v2/users/\(login)/coalitions"), as: [CoalitionRaw].self)
        async let usersResult: [CoalitionUserRaw] = api.request(Endpoint(path: "/v2/users/\(login)/coalitions_users"), as: [CoalitionUserRaw].self)
        
        let (fetchedCoalitions, fetchedUsers) = try await (coalitionsResult, usersResult)
        
        await cache.set(fetchedCoalitions, forKey: coalitionsKey, ttl: 600)
        await cache.set(fetchedUsers, forKey: usersKey, ttl: 600)
        
        return (fetchedCoalitions, fetchedUsers)
    }

    func fetchProjects(login: String) async throws -> [ProjectRaw] {
        let cacheKey = await cache.cacheKey(for: "/v2/users/\(login)/projects_users")
        
        if let cached = await cache.get([ProjectRaw].self, forKey: cacheKey) {
            return cached
        }
        
        let projects: [ProjectRaw] = try await api.pagedRequest { page in
            Endpoint(path: "/v2/users/\(login)/projects_users", queryItems: [URLQueryItem(name: "page", value: "\(page)")])
        }
        
        await cache.set(projects, forKey: cacheKey, ttl: 300)
        return projects
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
    
    func fetchCompleteProfile(login: String) async throws -> (UserProfile, [CoalitionRaw], [CoalitionUserRaw], [ProjectRaw]) {
        let completeKey = await cache.cacheKey(for: "/complete_profile/\(login)")
        
        if let cached = await cache.get(CachedCompleteProfile.self, forKey: completeKey) {
            return (cached.profile, cached.coalitions, cached.coalitionUsers, cached.projects)
        }
        
        async let profileResult = basicProfile(login: login)
        async let coalitionsResult = fetchCoalitions(login: login)
        async let projectsResult = fetchProjects(login: login)
        
        let profile = try await profileResult
        let coalitions = try await coalitionsResult
        let projects = try await projectsResult
        
        let cachedProfile = CachedCompleteProfile(
            profile: profile,
            coalitions: coalitions.0,
            coalitionUsers: coalitions.1,
            projects: projects
        )
        await cache.set(cachedProfile, forKey: completeKey, ttl: 600)
        
        return (profile, coalitions.0, coalitions.1, projects)
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
            let projectURL: URL?
            let status: String?
            let teamStatus: String?
            let registeredAt: Date?
            let endAt: Date?
            let finalMark: Int?
            let validated: Bool?
            let latestTeamInProgress: Bool
        }

        func mostRecentTeam(_ teams: [TeamRaw]) -> TeamRaw? {
            func score(_ t: TeamRaw) -> (Date, Int) {
                let d = DateParser.iso(t.updated_at) ?? DateParser.iso(t.created_at) ?? DateParser.iso(t.closed_at) ?? .distantPast
                let i = t.id ?? 0
                return (d, i)
            }
            return teams.max { l, r in
                let ls = score(l)
                let rs = score(r)
                if ls.0 == rs.0 { return ls.1 < rs.1 }
                return ls.0 < rs.0
            }
        }

        let normalized: [Norm] = projects.compactMap { p in
            guard let name = p.project.name, let slug = p.project.slug else { return nil }
            let latestTeam = p.teams.flatMap(mostRecentTeam)
            let finishedDates: [Date] = [
                DateParser.iso(p.closed_at),
                DateParser.iso(p.marked_at)
            ].compactMap { $0 } + (p.teams?.compactMap { DateParser.iso($0.closed_at) } ?? [])

            let endAt = finishedDates.max()
            let projectStatus = p.status?.lowercased()
            let latestTeamStatus = latestTeam?.status?.lowercased()
            let encodedSlug = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? slug
            let projectURL = URL(string: "https://projects.intra.42.fr/projects/\(encodedSlug)")
            return Norm(
                slug: slug,
                name: name,
                cursusId: p.cursus_ids.first,
                retry: p.occurrence,
                projectURL: projectURL,
                status: projectStatus,
                teamStatus: latestTeamStatus,
                registeredAt: DateParser.iso(p.created_at),
                endAt: endAt,
                finalMark: p.final_mark,
                validated: p.validated,
                latestTeamInProgress: latestTeamStatus == "in_progress"
            )
        }

        let finished: [UserProfile.Project] = normalized
            .filter { n in
                if n.latestTeamInProgress { return false }
                let st = n.status ?? ""
                let ts = n.teamStatus ?? ""
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
                    createdAt: n.registeredAt,
                    projectURL: n.projectURL
                )
            }
            .sorted { ($0.closedAt ?? .distantPast) > ($1.closedAt ?? .distantPast) }

        let active: [UserProfile.ActiveProject] = normalized
            .filter { n in
                if n.latestTeamInProgress { return true }
                let st = n.status ?? ""
                let ts = n.teamStatus ?? ""
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
                    repoURL: n.projectURL,
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
