import Foundation

struct UserInfoRaw: Decodable {
    let login: String
    let displayname: String
    let wallet: Int
    let correction_point: Int
    let image: ImageRaw
    let pool_month: String?
    let pool_year: String?
    let campus: [CampusRaw]?
    let kind: String?
    let achievements: [AchievementRaw]
    let is_active: Bool?
    let email: String?
    let phone: String?
    let titles_users: [TitleUserRaw]?
    let cursus_users: [CursusUserRaw]

    var image_url: String { image.link }
    var campus_name: String? { campus?.first?.name }
    var user_kind: String? { kind }
    var user_name_with_title: String? { login }
}

extension UserProfile {
    init(
        raw: UserInfoRaw,
        coalitions: [UserProfile.Coalition] = [],
        finishedProjects: [UserProfile.Project] = [],
        activeProjects: [UserProfile.ActiveProject] = [],
        currentHost: String? = nil
    ) {
        self.id = raw.login
        self.login = raw.login
        self.displayName = raw.displayname
        self.wallet = raw.wallet
        self.correctionPoint = raw.correction_point
        self.imageURL = URL(string: raw.image.link)
        self.poolMonth = raw.pool_month
        self.poolYear = raw.pool_year
        self.campusName = raw.campus?.first?.name
        self.userKind = raw.kind
        self.isActive = raw.is_active
        self.email = raw.email
        self.phone = raw.phone
        self.userNameWithTitle = raw.login
        self.currentHost = currentHost
        self.cursus = raw.cursus_users.map {
            UserProfile.Cursus(
                id: $0.cursus_id ?? 0,
                grade: $0.grade,
                level: $0.level,
                beginAt: ISO8601DateFormatter().date(from: $0.begin_at ?? ""),
                endAt: ISO8601DateFormatter().date(from: $0.end_at ?? ""),
                name: $0.cursus.name
            )
        }
        self.coalitions = coalitions
        self.achievements = raw.achievements.map {
            UserProfile.Achievement(
                id: $0.id,
                name: $0.name,
                description: $0.description,
                image: URL(string: $0.image)
            )
        }
        self.finishedProjects = finishedProjects
        self.activeProjects = activeProjects
    }
}

struct ImageRaw: Decodable {
    let link: String
}

struct CampusRaw: Decodable {
    let name: String
}

struct AchievementRaw: Decodable {
    let id: Int
    let name: String
    let description: String
    let image: String
}

struct TitleUserRaw: Decodable {
    let selected: Bool?
    let title_id: Int?
}

struct CursusUserRaw: Decodable {
    let cursus_id: Int?
    let grade: String?
    let level: Double?
    let begin_at: String?
    let end_at: String?
    let cursus: CursusRaw
}

struct CursusRaw: Decodable {
    let name: String?
}

struct CoalitionRaw: Decodable {
    let id: Int
    let name: String
    let slug: String
    let color: String
    let image_url: String
}

struct CoalitionUserRaw: Decodable {
    let coalition_id: Int
    let score: Int?
    let rank: Int?
}

struct ProjectRaw: Decodable {
    let final_mark: Int?
    let status: String?
    let closed_at: String?
    let marked_at: String?
    let validated: Bool?
    let occurrence: Int?
    let cursus_ids: [Int]
    let created_at: String?
    let project: ProjectInfoRaw
    let current_team_id: Int?
    let teams: [TeamRaw]?
}

struct ProjectInfoRaw: Decodable {
    let name: String?
    let slug: String?
}

struct TeamRaw: Decodable {
    let status: String?
}

struct LocationRaw: Decodable {
    let begin_at: String?
    let end_at: String?
    let host: String?
}
