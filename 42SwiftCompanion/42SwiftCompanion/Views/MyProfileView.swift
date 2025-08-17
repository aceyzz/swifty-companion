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
					VStack(spacing: 24) {
						SectionCard(title: "Identité") {
							if let url = profile.imageURL {
								AsyncImage(url: url) { image in
									image.resizable().aspectRatio(contentMode: .fit)
								} placeholder: {
									Color.gray.frame(width: 120, height: 120)
								}
								.frame(width: 120, height: 120)
							}
							ProfileTextGroup(texts: [profile.displayName], font: .title)
							ProfileTextGroup(texts: [profile.login], font: .subheadline)
						}
						SectionCard(title: "Contact et campus") {
							ProfileTextGroup(texts: profile.displayableContact, font: .subheadline)
						}
						SectionCard(title: "Statut et cursus") {
							ProfileTextGroup(texts: profile.displayableStatus, font: .subheadline)
						}
						SectionCard(title: "Points") {
							ProfileTextGroup(texts: ["Wallet: \(profile.wallet) | Points: \(profile.correctionPoint)"], font: .subheadline)
						}
						SectionCard(title: "Cursus") {
							ProfileTextGroup(texts: profile.displayableCursus)
						}
						SectionCard(title: "Coalitions") {
							ProfileTextGroup(texts: profile.displayableCoalitions)
						}
						SectionCard(title: "Succès") {
							ProfileTextGroup(texts: profile.displayableAchievements)
						}
						SectionCard(title: "Projets terminés") {
							ProfileTextGroup(texts: profile.displayableFinishedProjects)
						}
						SectionCard(title: "Projets en cours") {
							ProfileTextGroup(texts: profile.displayableActiveProjects)
						}
						SectionCard(title: "Poste") {
							ProfileTextGroup(texts: profile.displayableHost)
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

struct SectionCard<Content: View>: View {
	let title: String
	let content: Content
	init(title: String, @ViewBuilder content: () -> Content) {
		self.title = title
		self.content = content()
	}
	var body: some View {
		if let group = content as? ProfileTextGroup, group.isEmpty {
			EmptyView()
		} else {
			VStack(alignment: .leading, spacing: 12) {
				Text(title)
					.font(.system(size: 22, weight: .bold, design: .rounded))
					.foregroundStyle(Color.accentColor)
					.padding(.bottom, 4)
				content
			}
			.padding(20)
			.frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
			.background(
				RoundedRectangle(cornerRadius: 22, style: .continuous)
					.fill(Color.accentColor.opacity(0.08))
			)
			.overlay(
				RoundedRectangle(cornerRadius: 22, style: .continuous)
					.stroke(Color.accentColor.opacity(0.18), lineWidth: 1.5)
			)
			.shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
			.padding(.horizontal, 8)
		}
	}
}

struct ProfileTextGroup: View {
	let texts: [String]
	var font: Font = .body

	var isEmpty: Bool { texts.isEmpty || texts.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }

	var body: some View {
		if isEmpty {
			EmptyView()
		} else {
			VStack(alignment: .leading, spacing: 4) {
				ForEach(texts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, id: \.self) { text in
					Text(text)
						.font(font)
				}
			}
		}
	}
}
