import Foundation

struct UserProfile: Identifiable, Codable {
    let id: String
    let login: String
    let displayName: String
    let userNameWithTitle: String?
    let wallet: Int
    let correctionPoint: Int
    let imageURL: URL?
    let poolMonth: String?
    let poolYear: String?
    let campusId: Int?
    let campusName: String?
    let campusCity: String?
    let campusCountry: String?
    let campusTimeZone: String?
    let campusLanguage: String?
    let userKind: String?
    let isActive: Bool?
    let email: String?
    let phone: String?
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
        let count: Int?
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
        let projectURL: URL?
    }

    struct ActiveProject: Identifiable, Codable {
        let id: String
        let name: String
        let slug: String
        let status: String?
        let teamStatus: String?
        let repoURL: URL?
        let registeredAt: Date?
        let cursusId: Int?
        let retry: Int?
        let createdAt: Date?
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
        self.userNameWithTitle = raw.user_name_with_title
        self.wallet = raw.wallet
        self.correctionPoint = raw.correction_point
        self.imageURL = URL(string: raw.image.link)
        self.poolMonth = raw.pool_month
        self.poolYear = raw.pool_year
        self.campusId = raw.campus_id
        self.campusName = raw.campus_name
        self.campusCity = raw.campus_city
        self.campusCountry = raw.campus_country
        self.campusTimeZone = raw.campus_time_zone
        self.campusLanguage = raw.campus_language
        self.userKind = raw.user_kind
        self.isActive = raw.isActive
        self.email = raw.email
        self.phone = raw.phone
        self.currentHost = currentHost ?? (raw.location?.isEmpty == false ? raw.location : nil)
        self.cursus = raw.cursus_users.map {
            UserProfile.Cursus(
                id: $0.cursus_id ?? 0,
                grade: $0.grade,
                level: $0.level,
                beginAt: DateParser.iso($0.begin_at),
                endAt: DateParser.iso($0.end_at),
                name: $0.cursus.name
            )
        }
        self.coalitions = coalitions
        self.achievements = raw.achievements.map {
            let urlString = $0.image.hasPrefix("/") ? "https://api.intra.42.fr\($0.image)" : $0.image
            return UserProfile.Achievement(id: $0.id, name: $0.name, description: $0.description, image: URL(string: urlString), count: $0.nbr_of_success)
        }
        self.finishedProjects = finishedProjects
        self.activeProjects = activeProjects
    }

    func with(coalitions: [Coalition]) -> UserProfile {
        UserProfile(id: id, login: login, displayName: displayName, userNameWithTitle: userNameWithTitle, wallet: wallet, correctionPoint: correctionPoint, imageURL: imageURL, poolMonth: poolMonth, poolYear: poolYear, campusId: campusId, campusName: campusName, campusCity: campusCity, campusCountry: campusCountry, campusTimeZone: campusTimeZone, campusLanguage: campusLanguage, userKind: userKind, isActive: isActive, email: email, phone: phone, currentHost: currentHost, cursus: cursus, coalitions: coalitions, achievements: achievements, finishedProjects: finishedProjects, activeProjects: activeProjects)
    }

    func with(projectsFinished: [Project], projectsActive: [ActiveProject]) -> UserProfile {
        UserProfile(id: id, login: login, displayName: displayName, userNameWithTitle: userNameWithTitle, wallet: wallet, correctionPoint: correctionPoint, imageURL: imageURL, poolMonth: poolMonth, poolYear: poolYear, campusId: campusId, campusName: campusName, campusCity: campusCity, campusCountry: campusCountry, campusTimeZone: campusTimeZone, campusLanguage: campusLanguage, userKind: userKind, isActive: isActive, email: email, phone: phone, currentHost: currentHost, cursus: cursus, coalitions: coalitions, achievements: achievements, finishedProjects: projectsFinished, activeProjects: projectsActive)
    }

    func with(currentHost: String?) -> UserProfile {
        UserProfile(id: id, login: login, displayName: displayName, userNameWithTitle: userNameWithTitle, wallet: wallet, correctionPoint: correctionPoint, imageURL: imageURL, poolMonth: poolMonth, poolYear: poolYear, campusId: campusId, campusName: campusName, campusCity: campusCity, campusCountry: campusCountry, campusTimeZone: campusTimeZone, campusLanguage: campusLanguage, userKind: userKind, isActive: isActive, email: email, phone: phone, currentHost: currentHost, cursus: cursus, coalitions: coalitions, achievements: achievements, finishedProjects: finishedProjects, activeProjects: activeProjects)
    }
}

extension UserProfile {
    var displayableContact: [String] {
        var a: [String] = []
        if let email, !email.isEmpty { a.append(email) }
        if let phone, !phone.isEmpty, phone.lowercased() != "hidden" { a.append(phone) }
        if let campusName, !campusName.isEmpty {
            var campusLine = campusName
            if let city = campusCity, !city.isEmpty { campusLine += " — \(city)" }
            if let country = campusCountry, !country.isEmpty { campusLine += ", \(country)" }
            if let tz = campusTimeZone, !tz.isEmpty { campusLine += " (\(tz))" }
            a.append(campusLine)
        }
        return a
    }

    var displayableStatus: [String] {
        var arr: [String] = []
        if let kind = userKind, !kind.isEmpty { arr.append(kind.capitalized) }
        if let poolMonth = poolMonth, let poolYear = poolYear { arr.append("Piscine: \(poolMonth) \(poolYear)") }
        if let isActive = isActive { arr.append(isActive ? "Actif" : "Inactif") }
        return arr
    }

    var displayableCursus: [String] {
        cursus.sorted { ($0.level ?? 0) > ($1.level ?? 0) }.compactMap {
            var s = $0.name ?? "Cursus"
            if let level = $0.level { s += " — Niveau \(level.formatted(.number.precision(.fractionLength(2))))" }
            if let grade = $0.grade, !grade.isEmpty { s += " — \(grade)" }
            return s
        }
    }

    var displayableCoalitions: [String] {
        coalitions.map {
            var s = $0.name
            if let score = $0.score { s += " | Score: \(score)" }
            if let rank = $0.rank { s += " | Rang: \(rank)" }
            return s
        }
    }

    var displayableAchievements: [String] {
        achievements.map {
            if let c = $0.count, c > 1 { return "\($0.name) ×\(c)" }
            return $0.name
        }
    }

    var displayableFinishedProjects: [String] {
        finishedProjects.map {
            var s = "\($0.name) | Note: \($0.finalMark ?? 0)"
            if let v = $0.validated { s += " | Validé: \(v ? "Oui" : "Non")" }
            if let d = $0.closedAt { s += " | Fini le: \(Formatters.shortDate.string(from: d))" }
            return s
        }
    }

    var displayableActiveProjects: [String] {
        activeProjects.map {
            var s = "\($0.name) | Statut: \($0.status ?? "")"
            if let ts = $0.teamStatus { s += " | Équipe: \(ts)" }
            return s
        }
    }

    var displayableHost: [String] {
        guard let host = currentHost else { return [] }
        return ["Poste actuel: \(host)"]
    }

    var displayableHostOrNA: String {
        "Poste actuel: \(currentHost?.isEmpty == false ? currentHost! : "Non disponible")"
    }

    enum Formatters {
        static let shortDate: DateFormatter = {
            let df = DateFormatter()
            df.calendar = Calendar(identifier: .gregorian)
            df.locale = Locale.current
            df.dateStyle = .medium
            df.timeStyle = .none
            return df
        }()
    }
}

struct ImageRaw: Decodable { let link: String }

struct CampusLanguageRaw: Decodable { let name: String?; let identifier: String? }

struct CampusRaw: Decodable {
    let id: Int?
    let name: String
    let time_zone: String?
    let city: String?
    let country: String?
    let website: String?
    let language: CampusLanguageRaw?
}

struct AchievementRaw: Decodable {
    let id: Int
    let name: String
    let description: String
    let image: String
    let nbr_of_success: Int?
}

struct TitleRaw: Decodable { let id: Int; let name: String }

struct TitleUserRaw: Decodable { let selected: Bool?; let title_id: Int? }

struct CursusRaw: Decodable { let name: String? }

struct CursusUserRaw: Decodable {
    let cursus_id: Int?
    let grade: String?
    let level: Double?
    let begin_at: String?
    let end_at: String?
    let cursus: CursusRaw
}

struct CoalitionRaw: Decodable { let id: Int; let name: String; let slug: String; let color: String; let image_url: String; let score: Int? }

struct CoalitionUserRaw: Decodable { let coalition_id: Int; let score: Int?; let rank: Int? }

struct TeamRaw: Decodable {
    let id: Int?
    let status: String?
    let url: String?
    let repo_url: String?
    let name: String?
    let created_at: String?
    let updated_at: String?
    let closed_at: String?
    let validated: Bool?
}

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
    let email: String?
    let phone: String?
    let titles: [TitleRaw]?
    let titles_users: [TitleUserRaw]?
    let cursus_users: [CursusUserRaw]
    let location: String?
    let isActive: Bool?

    var image_url: String { image.link }
    var campus_id: Int? { campus?.first?.id }
    var campus_name: String? { campus?.first?.name }
    var campus_city: String? { campus?.first?.city }
    var campus_country: String? { campus?.first?.country }
    var campus_time_zone: String? { campus?.first?.time_zone }
    var campus_language: String? { campus?.first?.language?.name }
    var user_kind: String? { kind }
    var user_name_with_title: String? {
        guard let tuser = titles_users?.first(where: { $0.selected == true }),
              let tid = tuser.title_id,
              let template = titles?.first(where: { $0.id == tid })?.name
        else { return login }
        return template.replacingOccurrences(of: "%login", with: login)
    }

    private enum CodingKeys: String, CodingKey {
        case login, displayname, wallet, correction_point, image, pool_month, pool_year, campus, kind, achievements, email, phone, titles, titles_users, cursus_users, location
        case activeQuestion = "active?"
        case isActiveLegacy = "is_active"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        login = try c.decode(String.self, forKey: .login)
        displayname = try c.decode(String.self, forKey: .displayname)
        wallet = try c.decode(Int.self, forKey: .wallet)
        correction_point = try c.decode(Int.self, forKey: .correction_point)
        image = try c.decode(ImageRaw.self, forKey: .image)
        pool_month = try? c.decode(String.self, forKey: .pool_month)
        pool_year = try? c.decode(String.self, forKey: .pool_year)
        campus = try? c.decode([CampusRaw].self, forKey: .campus)
        kind = try? c.decode(String.self, forKey: .kind)
        achievements = (try? c.decode([AchievementRaw].self, forKey: .achievements)) ?? []
        email = try? c.decode(String.self, forKey: .email)
        phone = try? c.decode(String.self, forKey: .phone)
        titles = try? c.decode([TitleRaw].self, forKey: .titles)
        titles_users = try? c.decode([TitleUserRaw].self, forKey: .titles_users)
        cursus_users = (try? c.decode([CursusUserRaw].self, forKey: .cursus_users)) ?? []
        location = try? c.decode(String.self, forKey: .location)
        let aNew = try? c.decode(Bool.self, forKey: .activeQuestion)
        let aOld = try? c.decode(Bool.self, forKey: .isActiveLegacy)
        isActive = aNew ?? aOld
    }
}

struct UserSummary: Identifiable, Codable, Equatable {
    let login: String
    let displayName: String?
    let imageURL: URL?
    let primaryCampusId: Int?
    var id: String { login }
}

extension UserSummary {
    static func fromRaw(_ r: UserSummaryRaw) -> UserSummary {
        let urlStr = r.image?.link ?? r.image_url
        return .init(login: r.login, displayName: r.displayname, imageURL: urlStr.flatMap(URL.init(string:)), primaryCampusId: r.primary_campus_id)
    }
}

struct UserSummaryRaw: Decodable {
    struct ImageObj: Decodable { let link: String? }
    let id: Int?
    let login: String
    let displayname: String?
    let image_url: String?
    let image: ImageObj?
    let primary_campus_id: Int?
}

struct UpcomingScaleTeamRaw: Decodable, Identifiable {
    struct ScaleRaw: Decodable {
        let introduction_md: String?
        let guidelines_md: String?
        let disclaimer_md: String?
        let duration: Int?
    }

    struct TeamRaw: Decodable { let project_id: Int? }
    let id: Int
    let begin_at: String?
    let correcteds: JSONValue?
    let corrector: JSONValue?
    let scale: ScaleRaw?
    let team: TeamRaw?
}

struct DisplaySlot: Identifiable, Equatable {
    let id: String
    let slotIds: [Int]
    let begin: Date?
    let end: Date?
    let isReserved: Bool
    let scaleTeamId: Int?
    var scaleTeam: JSONValue?
}

struct EvaluationSlot: Codable, Identifiable, Equatable {
    let id: Int
    let begin_at: String?
    let end_at: String?
    let scale_team: JSONValue?
    let user: JSONValue?
}

struct Me: Decodable { let id: Int }

struct UpcomingEvaluation: Identifiable, Equatable {
    enum Role { case corrector, corrected }
    let id: Int
    let role: Role
    let beginAt: Date?
    let endAt: Date?
    let projectName: String?
    let correctedLogins: [String]
    let correctorLogin: String?
    let introLine: String?
    let guidelinesLine: String?
    let disclaimerLine: String?
    let durationMinutes: Int
}
