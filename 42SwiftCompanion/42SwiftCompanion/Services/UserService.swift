import Foundation

final class DataLoader: NSObject, URLSessionDataDelegate {
	private var completion: ((Result<(Data, URLResponse), Error>) -> Void)?
	private var receivedData = Data()
	private var response: URLResponse?

	func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
		try await withCheckedThrowingContinuation { continuation in
			self.completion = { result in
				switch result {
				case .success(let tuple):
					continuation.resume(returning: tuple)
				case .failure(let error):
					continuation.resume(throwing: error)
				}
			}
			let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
			let task = session.dataTask(with: request)
			task.resume()
		}
	}

	func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
		receivedData.append(data)
	}

	func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
		self.response = response
		completionHandler(.allow)
	}

	func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		if let error = error {
			completion?(.failure(error))
		} else if let response = response {
			completion?(.success((receivedData, response)))
		} else {
			completion?(.failure(URLError(.badServerResponse)))
		}
		completion = nil
		receivedData = Data()
		response = nil
	}
}

protocol APIRequest {
	func makeRequest(for user: String, page: Int?) -> URLRequest?
}

struct UserInfoRequest: APIRequest {
	func makeRequest(for user: String, page: Int? = nil) -> URLRequest? {
		guard let token = AuthService.shared.accessToken else { return nil }
		guard let url = URL(string: "https://api.intra.42.fr/v2/users/\(user)") else { return nil }
		var request = URLRequest(url: url)
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		return request
	}
}

struct UserTitlesRequest: APIRequest {
	func makeRequest(for user: String, page: Int? = nil) -> URLRequest? {
		guard let token = AuthService.shared.accessToken else { return nil }
		guard let url = URL(string: "https://api.intra.42.fr/v2/titles") else { return nil }
		var request = URLRequest(url: url)
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		return request
	}
}

struct UserCoalitionsRequest: APIRequest {
	func makeRequest(for user: String, page: Int? = nil) -> URLRequest? {
		guard let token = AuthService.shared.accessToken else { return nil }
		guard let url = URL(string: "https://api.intra.42.fr/v2/users/\(user)/coalitions") else { return nil }
		var request = URLRequest(url: url)
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		return request
	}
}

struct UserCoalitionsUsersRequest: APIRequest {
	func makeRequest(for user: String, page: Int? = nil) -> URLRequest? {
		guard let token = AuthService.shared.accessToken else { return nil }
		guard let url = URL(string: "https://api.intra.42.fr/v2/users/\(user)/coalitions_users") else { return nil }
		var request = URLRequest(url: url)
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		return request
	}
}

struct UserProjectsRequest: APIRequest {
	func makeRequest(for user: String, page: Int? = nil) -> URLRequest? {
		guard let token = AuthService.shared.accessToken else { return nil }
		var urlString = "https://api.intra.42.fr/v2/users/\(user)/projects_users"
		if let page = page { urlString += "?page=\(page)" }
		guard let url = URL(string: urlString) else { return nil }
		var request = URLRequest(url: url)
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		return request
	}
}

final class UserService {
	private let pageSize = 15
	private let apiRateLimitDelay: UInt64 = 700_000_000

	private func rateLimit() async {
		try? await Task.sleep(nanoseconds: apiRateLimitDelay)
	}
	static let shared = UserService()
	private init() {}

	private func authorizedRequest(url: URL) throws -> URLRequest {
		guard let token = AuthService.shared.accessToken, !token.isEmpty else { throw URLError(.userAuthenticationRequired) }
		var request = URLRequest(url: url)
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		return request
	}

	private func fetchPaged<T: Decodable>(_ request: APIRequest, user: String, type: T.Type) async throws -> [T] {
		var results: [T] = []
		var page = 1
		while true {
			guard let urlRequest = request.makeRequest(for: user, page: page) else { break }
			let (data, response) = try await URLSession.shared.data(for: urlRequest)
			if let http = response as? HTTPURLResponse {
				guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
			}
			let pageResults = try JSONDecoder().decode([T].self, from: data)
			if pageResults.isEmpty { break }
			results.append(contentsOf: pageResults)
			if pageResults.count < pageSize { break }
			print("(Page\(page)) Status code: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
			page += 1
			await rateLimit()
		}
		return results
	}

	private func fetchSingle<T: Decodable>(_ request: APIRequest, user: String, type: T.Type) async throws -> T {
		guard let urlRequest = request.makeRequest(for: user, page: nil) else { throw URLError(.badURL) }
		let (data, response) = try await URLSession.shared.data(for: urlRequest)
		if let http = response as? HTTPURLResponse {
			guard http.statusCode == 200 else { print("Error fetching \(user): \(http.statusCode)"); throw URLError(.badServerResponse) }
		}
		print("Status code: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
		return try JSONDecoder().decode(T.self, from: data)
	}

	func fetchFullProfile(login: String) async throws -> UserProfile {
		print("Fetch user info for \(login)")
		let user: UserInfoRaw = try await fetchSingle(UserInfoRequest(), user: login, type: UserInfoRaw.self)
		await rateLimit()
		print("Fetch coalitions for \(login)")
		let coalitionsList: [CoalitionRaw] = try await fetchSingle(UserCoalitionsRequest(), user: login, type: [CoalitionRaw].self)
		await rateLimit()
		print("Fetch coalitions users for \(login)")
		let coalitionsUsersList: [CoalitionUserRaw] = try await fetchSingle(UserCoalitionsUsersRequest(), user: login, type: [CoalitionUserRaw].self)
		await rateLimit()
		print("Fetch projects for \(login)")
		let projectsList: [ProjectRaw] = try await fetchPaged(UserProjectsRequest(), user: login, type: ProjectRaw.self)
		await rateLimit()

		let cursus: [UserProfile.Cursus] = user.cursus_users.map {
			UserProfile.Cursus(
				id: $0.cursus_id ?? 0,
				grade: $0.grade,
				level: $0.level,
				beginAt: ISO8601DateFormatter().date(from: $0.begin_at ?? ""),
				endAt: ISO8601DateFormatter().date(from: $0.end_at ?? ""),
				name: $0.cursus.name
			)
		}

		let coalitionsMerged: [UserProfile.Coalition] = coalitionsList.map { coalition in
			let userStatus = coalitionsUsersList.first { $0.coalition_id == coalition.id }
			return UserProfile.Coalition(
				id: coalition.id,
				name: coalition.name,
				slug: coalition.slug,
				color: coalition.color,
				imageURL: URL(string: coalition.image_url),
				score: userStatus?.score,
				rank: userStatus?.rank
			)
		}

		let achievements: [UserProfile.Achievement] = user.achievements.map {
			UserProfile.Achievement(
				id: $0.id,
				name: $0.name,
				description: $0.description,
				image: URL(string: $0.image)
			)
		}

		let finishedProjects: [UserProfile.Project] = projectsList.filter {
			$0.final_mark != nil &&
			($0.status == "finished" || $0.status == "waiting_for_correction") &&
			($0.closed_at != nil || $0.marked_at != nil)
		}.compactMap { project in
			guard let name = project.project.name, let slug = project.project.slug else { return nil }
			return UserProfile.Project(
				id: slug,
				name: name,
				slug: slug,
				finalMark: project.final_mark,
				validated: project.validated,
				closedAt: ISO8601DateFormatter().date(from: project.closed_at ?? project.marked_at ?? ""),
				retry: project.occurrence,
				cursusId: project.cursus_ids.first,
				createdAt: ISO8601DateFormatter().date(from: project.created_at ?? "")
			)
		}.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }

		let activeProjects: [UserProfile.ActiveProject] = projectsList.filter {
			$0.final_mark == nil &&
			$0.current_team_id != nil &&
			($0.teams?.isEmpty == false)
		}.compactMap { project in
			guard let name = project.project.name, let slug = project.project.slug else { return nil }
			return UserProfile.ActiveProject(
				id: slug,
				name: name,
				slug: slug,
				status: project.status,
				teamStatus: project.teams?.first?.status,
				registeredAt: ISO8601DateFormatter().date(from: project.created_at ?? ""),
				cursusId: project.cursus_ids.first,
				retry: project.occurrence,
				createdAt: ISO8601DateFormatter().date(from: project.created_at ?? "")
			)
		}.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }

		return UserProfile(
			id: user.login,
			login: user.login,
			displayName: user.displayname,
			wallet: user.wallet,
			correctionPoint: user.correction_point,
			imageURL: URL(string: user.image.link),
			poolMonth: user.pool_month,
			poolYear: user.pool_year,
			campusName: user.campus?.first?.name,
			userKind: user.kind,
			isActive: user.is_active,
			email: user.email,
			phone: user.phone,
			userNameWithTitle: nil,
			currentHost: nil,
			cursus: cursus,
			coalitions: coalitionsMerged,
			achievements: achievements,
			finishedProjects: finishedProjects,
			activeProjects: activeProjects
		)
	}
}

private extension DateFormatter {
	static let dayFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateFormat = "yyyy-MM-dd"
		formatter.timeZone = TimeZone(secondsFromGMT: 0)
		return formatter
	}()
}
