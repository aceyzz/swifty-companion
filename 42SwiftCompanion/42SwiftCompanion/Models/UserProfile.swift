extension UserProfile {
	var displayableContact: [String] {
		[email, phone, campusName].compactMap { $0?.isEmpty == false ? $0 : nil }
	}

	var displayableStatus: [String] {
		var arr: [String] = []
		if let kind = userKind, !kind.isEmpty {
			arr.append(kind.capitalized)
		}
		if let poolMonth = poolMonth, let poolYear = poolYear {
			arr.append("Piscine: \(poolMonth) \(poolYear)")
		}
		if let isActive = isActive {
			arr.append(isActive ? "Actif" : "Inactif")
		}
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
}

import Foundation

struct UserProfile: Identifiable {
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

	struct Cursus: Identifiable {
		let id: Int
		let grade: String?
		let level: Double?
		let beginAt: Date?
		let endAt: Date?
		let name: String?
	}

	struct Coalition: Identifiable {
		let id: Int
		let name: String
		let slug: String
		let color: String
		let imageURL: URL?
		let score: Int?
		let rank: Int?
	}

	struct Achievement: Identifiable {
		let id: Int
		let name: String
		let description: String
		let image: URL?
	}

	struct Project: Identifiable {
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

	struct ActiveProject: Identifiable {
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
