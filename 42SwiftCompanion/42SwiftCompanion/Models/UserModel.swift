import Foundation

struct UserProfile: Identifiable, Codable {
    let id: String
    let login: String
    let displayName: String
    let wallet: Int
    let correctionPoint: Int
    let imageURL: URL?
    let poolMonth: String?
    let poolYear: String?
    let campusName: String?
    let userKind: String?
    let isActive: Bool?
    let email: String?
    let phone: String?
    let userNameWithTitle: String?
    let currentHost: String?
    let cursus: [Cursus]
    let coalitions: [Coalition]
    let achievements: [Achievement]
    let finishedProjects: [Project]
    let activeProjects: [ActiveProject]

    struct Cursus: Identifiable, Codable {
        let id: Int
        let grade: String?
        let level: Double?
        let beginAt: Date?
        let endAt: Date?
        let name: String?
    }

    struct Coalition: Identifiable, Codable {
        let id: Int
        let name: String
        let slug: String
        let color: String
        let imageURL: URL?
        let score: Int?
        let rank: Int?
    }

    struct Achievement: Identifiable, Codable {
        let id: Int
        let name: String
        let description: String
        let image: URL?
    }

    struct Project: Identifiable, Codable {
        let id: String
        let name: String
        let slug: String
        let finalMark: Int?
        let validated: Bool?
        let closedAt: Date?
        let retry: Int?
        let cursusId: Int?
        let createdAt: Date?
    }

    struct ActiveProject: Identifiable, Codable {
        let id: String
        let name: String
        let slug: String
        let status: String?
        let teamStatus: String?
        let registeredAt: Date?
        let cursusId: Int?
        let retry: Int?
        let createdAt: Date?
    }
}

extension UserProfile {
    var displayableContact: [String] {
        [email, phone, campusName].compactMap { $0?.isEmpty == false ? $0 : nil }
    }
    var displayableStatus: [String] {
        var arr: [String] = []
        if let kind = userKind, !kind.isEmpty { arr.append(kind.capitalized) }
        if let poolMonth = poolMonth, let poolYear = poolYear { arr.append("Piscine: \(poolMonth) \(poolYear)") }
        if let isActive = isActive { arr.append(isActive ? "Actif" : "Inactif") }
        return arr
    }
    var displayableCursus: [String] {
        cursus.compactMap { $0.name ?? "Cursus" }
    }
    var displayableCoalitions: [String] {
        coalitions.map { "\($0.name) | Score: \($0.score ?? 0)" }
    }
    var displayableAchievements: [String] {
        achievements.map { $0.name }
    }
    var displayableFinishedProjects: [String] {
        finishedProjects.map { "\($0.name) | Note: \($0.finalMark ?? 0)" }
    }
    var displayableActiveProjects: [String] {
        activeProjects.map { "\($0.name) | Statut: \($0.status ?? "")" }
    }
    var displayableHost: [String] {
        guard let host = currentHost else { return [] }
        return ["Poste actuel: \(host)"]
    }
    var displayableHostOrNA: String {
        "Poste actuel: \(currentHost?.isEmpty == false ? currentHost! : "Non disponible")"
    }
}

struct ImageRaw: Decodable { let link: String }
struct CampusRaw: Decodable { let name: String }
struct AchievementRaw: Decodable { let id: Int; let name: String; let description: String; let image: String }
struct TitleUserRaw: Decodable { let selected: Bool?; let title_id: Int? }
struct CursusRaw: Decodable { let name: String? }
struct CursusUserRaw: Decodable { let cursus_id: Int?; let grade: String?; let level: Double?; let begin_at: String?; let end_at: String?; let cursus: CursusRaw }
struct CoalitionRaw: Decodable { let id: Int; let name: String; let slug: String; let color: String; let image_url: String }
struct CoalitionUserRaw: Decodable { let coalition_id: Int; let score: Int?; let rank: Int? }
struct TeamRaw: Decodable { let status: String? }
struct ProjectInfoRaw: Decodable { let name: String?; let slug: String? }
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
struct LocationRaw: Decodable { let id: Int?; let begin_at: String?; let end_at: String?; let host: String? }
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

enum DateParser {
    private static let fUTCFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let fUTC: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    static func iso(_ str: String?) -> Date? {
        guard let s = str, !s.isEmpty else { return nil }
        return fUTCFrac.date(from: s) ?? fUTC.date(from: s)
    }
    static func isoString(_ date: Date) -> String {
        fUTCFrac.string(from: date)
    }
}

extension UserProfile {
    init(raw: UserInfoRaw,
         coalitions: [UserProfile.Coalition] = [],
         finishedProjects: [UserProfile.Project] = [],
         activeProjects: [UserProfile.ActiveProject] = [],
         currentHost: String? = nil) {
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
            UserProfile.Cursus(id: $0.cursus_id ?? 0,
                               grade: $0.grade,
                               level: $0.level,
                               beginAt: DateParser.iso($0.begin_at),
                               endAt: DateParser.iso($0.end_at),
                               name: $0.cursus.name)
        }
        self.coalitions = coalitions
        self.achievements = raw.achievements.map {
            UserProfile.Achievement(id: $0.id,
                                    name: $0.name,
                                    description: $0.description,
                                    image: URL(string: $0.image))
        }
        self.finishedProjects = finishedProjects
        self.activeProjects = activeProjects
    }

    func with(coalitions: [Coalition]) -> UserProfile {
        UserProfile(id: id, login: login, displayName: displayName, wallet: wallet, correctionPoint: correctionPoint, imageURL: imageURL, poolMonth: poolMonth, poolYear: poolYear, campusName: campusName, userKind: userKind, isActive: isActive, email: email, phone: phone, userNameWithTitle: userNameWithTitle, currentHost: currentHost, cursus: cursus, coalitions: coalitions, achievements: achievements, finishedProjects: finishedProjects, activeProjects: activeProjects)
    }

    func with(projectsFinished: [Project], projectsActive: [ActiveProject]) -> UserProfile {
        UserProfile(id: id, login: login, displayName: displayName, wallet: wallet, correctionPoint: correctionPoint, imageURL: imageURL, poolMonth: poolMonth, poolYear: poolYear, campusName: campusName, userKind: userKind, isActive: isActive, email: email, phone: phone, userNameWithTitle: userNameWithTitle, currentHost: currentHost, cursus: cursus, coalitions: coalitions, achievements: achievements, finishedProjects: projectsFinished, activeProjects: projectsActive)
    }

    func with(currentHost: String?) -> UserProfile {
        UserProfile(id: id, login: login, displayName: displayName, wallet: wallet, correctionPoint: correctionPoint, imageURL: imageURL, poolMonth: poolMonth, poolYear: poolYear, campusName: campusName, userKind: userKind, isActive: isActive, email: email, phone: phone, userNameWithTitle: userNameWithTitle, currentHost: currentHost, cursus: cursus, coalitions: coalitions, achievements: achievements, finishedProjects: finishedProjects, activeProjects: activeProjects)
    }
}
