
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
