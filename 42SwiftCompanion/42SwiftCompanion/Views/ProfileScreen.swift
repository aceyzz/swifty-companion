import SwiftUI

@MainActor
final class MyProfileViewModel: ObservableObject {
	@Published var profile: UserProfile?
	@Published var isLoading = false
	@Published var error: String?
	private var lastFetch: Date?
	private let cooldown: TimeInterval = 30
	private let repo: ProfileRepository

	init(repo: ProfileRepository = .shared) {
		self.repo = repo
	}

	func fetchProfile() async {
		guard !isLoading else { return }
		if let last = lastFetch, Date().timeIntervalSince(last) < cooldown { return }
		isLoading = true
		error = nil
		do {
			profile = try await repo.myProfile()
			lastFetch = Date()
		} catch {
			self.error = error.localizedDescription
		}
		isLoading = false
	}
}

struct MyProfileView: View {
	@StateObject private var viewModel = MyProfileViewModel()

	var body: some View {
		VStack {
			if viewModel.isLoading {
				ProgressView()
			} else if let profile = viewModel.profile {
				ScrollView {
					VStack(spacing: 24) {
						SectionCard(title: "Identité") {
							VStack(spacing: 8) {
								if let url = profile.imageURL {
									AsyncImage(url: url) { image in
										image.resizable().aspectRatio(contentMode: .fit)
									} placeholder: {
										Color.gray.frame(width: 120, height: 120)
									}
									.frame(width: 120, height: 120)
								}
								ProfileTextList(texts: [profile.displayName], font: .title)
								ProfileTextList(texts: [profile.login], font: .subheadline)
							}
						}
						if !profile.displayableContact.isEmpty {
							SectionCard(title: "Contact et campus") {
								ProfileTextList(texts: profile.displayableContact, font: .subheadline)
							}
						}
						if !profile.displayableStatus.isEmpty {
							SectionCard(title: "Statut et cursus") {
								ProfileTextList(texts: profile.displayableStatus, font: .subheadline)
							}
						}
						SectionCard(title: "Points") {
							ProfileTextList(texts: ["Wallet: \(profile.wallet) | Points: \(profile.correctionPoint)"], font: .subheadline)
						}
						if !profile.displayableCursus.isEmpty {
							SectionCard(title: "Cursus") {
								ProfileTextList(texts: profile.displayableCursus)
							}
						}
						if !profile.displayableCoalitions.isEmpty {
							SectionCard(title: "Coalitions") {
								ProfileTextList(texts: profile.displayableCoalitions)
							}
						}
						if !profile.displayableAchievements.isEmpty {
							SectionCard(title: "Succès") {
								ProfileTextList(texts: profile.displayableAchievements)
							}
						}
						if !profile.displayableFinishedProjects.isEmpty {
							SectionCard(title: "Projets terminés") {
								ProfileTextList(texts: profile.displayableFinishedProjects)
							}
						}
						if !profile.displayableActiveProjects.isEmpty {
							SectionCard(title: "Projets en cours") {
								ProfileTextList(texts: profile.displayableActiveProjects)
							}
						}
						if !profile.displayableHost.isEmpty {
							SectionCard(title: "Poste") {
								ProfileTextList(texts: profile.displayableHost)
							}
						}
					}
					.padding()
				}
			} else if let error = viewModel.error {
				Text(error).foregroundColor(.red)
			} else {
				Text("Aucune donnée utilisateur")
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.task { await viewModel.fetchProfile() }
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

struct ProfileTextList: View {
	let texts: [String]
	var font: Font = .body

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			ForEach(texts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, id: \.self) { text in
				Text(text).font(font)
			}
		}
	}
}
