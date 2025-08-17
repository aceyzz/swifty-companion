import SwiftUI
import Foundation

@MainActor
final class MyProfileViewModel: ObservableObject {
	@Published var profile: UserProfile?
	@Published var isLoading = false
	@Published var error: String?
	private var lastFetch: Date?
	private let cooldown: TimeInterval = 30
	@Published var login: String = ""

	init(login: String) {
		if !login.isEmpty {
			self.login = login
		} else {
			self.login = AuthService.shared.getCurrentUserLogin()
		}
	}

	func fetchProfile() async {
		guard !isLoading else { return }
		if let last = lastFetch, Date().timeIntervalSince(last) < cooldown { return }
		isLoading = true
		error = nil
		do {
			let profile = try await MyProfileService.shared.fetchMyProfile()
			self.profile = profile
			lastFetch = Date()
		} catch {
			self.error = error.localizedDescription
		}
		isLoading = false
	}
}

struct MyProfileView: View {
	@StateObject private var viewModel: MyProfileViewModel

	init() {
		let login = AuthService.shared.isAuthenticated ? AuthService.shared.getCurrentUserLogin() : ""
		self._viewModel = StateObject(wrappedValue: MyProfileViewModel(login: login))
	}

	var body: some View {
		VStack {
			if viewModel.isLoading {
				ProgressView()
			} else if let profile = viewModel.profile {
				ScrollView {
					VStack(spacing: 16) {
						if let url = profile.imageURL {
							AsyncImage(url: url) { image in
								image.resizable().aspectRatio(contentMode: .fit)
							} placeholder: {
								Color.gray.frame(width: 120, height: 120)
							}
							.frame(width: 120, height: 120)
						}
						Text(profile.displayName)
							.font(.title)
						Text(profile.login)
							.font(.subheadline)
						Text("Wallet: \(profile.wallet) | Points: \(profile.correctionPoint)")
							.font(.subheadline)
						if !profile.cursus.isEmpty {
							VStack(alignment: .leading, spacing: 4) {
								Text("Cursus:")
								ForEach(profile.cursus) { cursus in
									Text(cursus.name ?? "Cursus")
								}
							}
						}
						if !profile.coalitions.isEmpty {
							VStack(alignment: .leading, spacing: 4) {
								Text("Coalitions:")
								ForEach(profile.coalitions) { coalition in
									Text("\(coalition.name) | Score: \(coalition.score ?? 0)")
								}
							}
						}
						if !profile.achievements.isEmpty {
							VStack(alignment: .leading, spacing: 4) {
								Text("Succès:")
								ForEach(profile.achievements) { a in
									Text(a.name)
								}
							}
						}
						if !profile.finishedProjects.isEmpty {
							VStack(alignment: .leading, spacing: 4) {
								Text("Projets terminés:")
								ForEach(profile.finishedProjects) { p in
									Text("\(p.name) | Note: \(p.finalMark ?? 0)")
								}
							}
						}
						if !profile.activeProjects.isEmpty {
							VStack(alignment: .leading, spacing: 4) {
								Text("Projets en cours:")
								ForEach(profile.activeProjects) { p in
									Text("\(p.name) | Statut: \(p.status ?? "")")
								}
							}
						}
						if let host = profile.currentHost {
							Text("Poste actuel: \(host)")
						}
					}
					.padding()
				}
			} else if let error = viewModel.error {
				Text(error)
					.foregroundColor(.red)
			} else {
				Text("Aucune donnée utilisateur")
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.task {
			await viewModel.fetchProfile()
		}
	}
}
