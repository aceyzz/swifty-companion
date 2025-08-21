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
        cursus.compactMap {
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
            if $0.repoURL != nil { s += " | Dépôt: Oui" }
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

struct TeamRaw: Decodable { let status: String?; let repo_url: String?; let name: String? }

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
    let titles: [TitleRaw]?
    let titles_users: [TitleUserRaw]?
    let cursus_users: [CursusUserRaw]

    var image_url: String { image.link }
    var campus_name: String? { campus?.first?.name }
    var campus_city: String? { campus?.first?.city }
    var campus_country: String? { campus?.first?.country }
    var campus_time_zone: String? { campus?.first?.time_zone }
    var campus_language: String? { campus?.first?.language?.name }
    var user_kind: String? { kind }
    var user_name_with_title: String? {
        guard let tuser = titles_users?.first(where: { $0.selected == true }), let tid = tuser.title_id, let template = titles?.first(where: { $0.id == tid })?.name else { return login }
        return template.replacingOccurrences(of: "%login", with: login)
    }
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
        self.userNameWithTitle = raw.user_name_with_title
        self.wallet = raw.wallet
        self.correctionPoint = raw.correction_point
        self.imageURL = URL(string: raw.image.link)
        self.poolMonth = raw.pool_month
        self.poolYear = raw.pool_year
        self.campusName = raw.campus_name
        self.campusCity = raw.campus_city
        self.campusCountry = raw.campus_country
        self.campusTimeZone = raw.campus_time_zone
        self.campusLanguage = raw.campus_language
        self.userKind = raw.kind
        self.isActive = raw.is_active
        self.email = raw.email
        self.phone = raw.phone
        self.currentHost = currentHost
        self.cursus = raw.cursus_users.map {
            UserProfile.Cursus(id: $0.cursus_id ?? 0, grade: $0.grade, level: $0.level, beginAt: DateParser.iso($0.begin_at), endAt: DateParser.iso($0.end_at), name: $0.cursus.name)
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
        UserProfile(id: id, login: login, displayName: displayName, userNameWithTitle: userNameWithTitle, wallet: wallet, correctionPoint: correctionPoint, imageURL: imageURL, poolMonth: poolMonth, poolYear: poolYear, campusName: campusName, campusCity: campusCity, campusCountry: campusCountry, campusTimeZone: campusTimeZone, campusLanguage: campusLanguage, userKind: userKind, isActive: isActive, email: email, phone: phone, currentHost: currentHost, cursus: cursus, coalitions: coalitions, achievements: achievements, finishedProjects: finishedProjects, activeProjects: activeProjects)
    }

    func with(projectsFinished: [Project], projectsActive: [ActiveProject]) -> UserProfile {
        UserProfile(id: id, login: login, displayName: displayName, userNameWithTitle: userNameWithTitle, wallet: wallet, correctionPoint: correctionPoint, imageURL: imageURL, poolMonth: poolMonth, poolYear: poolYear, campusName: campusName, campusCity: campusCity, campusCountry: campusCountry, campusTimeZone: campusTimeZone, campusLanguage: campusLanguage, userKind: userKind, isActive: isActive, email: email, phone: phone, currentHost: currentHost, cursus: cursus, coalitions: coalitions, achievements: achievements, finishedProjects: projectsFinished, activeProjects: projectsActive)
    }

    func with(currentHost: String?) -> UserProfile {
        UserProfile(id: id, login: login, displayName: displayName, userNameWithTitle: userNameWithTitle, wallet: wallet, correctionPoint: correctionPoint, imageURL: imageURL, poolMonth: poolMonth, poolYear: poolYear, campusName: campusName, campusCity: campusCity, campusCountry: campusCountry, campusTimeZone: campusTimeZone, campusLanguage: campusLanguage, userKind: userKind, isActive: isActive, email: email, phone: phone, currentHost: currentHost, cursus: cursus, coalitions: coalitions, achievements: achievements, finishedProjects: finishedProjects, activeProjects: activeProjects)
    }
}
