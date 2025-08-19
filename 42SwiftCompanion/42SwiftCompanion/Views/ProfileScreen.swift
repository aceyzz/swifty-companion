import SwiftUI

struct MyProfileView: View {
    @EnvironmentObject var profileStore: ProfileStore

    var body: some View {
        VStack {
            if let profile = profileStore.profile {
                ScrollView {
                    VStack(spacing: 24) {
                        SectionCard(title: "Identité") {
                            VStack(spacing: 8) {
                                if let url = profile.imageURL {
                                    AsyncImage(url: url) { image in
                                        image.resizable().aspectRatio(contentMode: .fit)
                                    } placeholder: {
                                        Color.gray.frame(width: 120, height: 120).clipShape(RoundedRectangle(cornerRadius: 16))
                                    }
                                    .frame(width: 120, height: 120)
                                } else {
                                    Color.gray.frame(width: 120, height: 120).clipShape(RoundedRectangle(cornerRadius: 16)).redacted(reason: .placeholder)
                                }
                                ProfileTextList(texts: [profile.displayName], font: .title)
                                ProfileTextList(texts: [profile.login], font: .subheadline)
                            }
                        }
                        SectionCard(title: "Contact et campus") {
                            if profile.displayableContact.isEmpty {
                                LoadingListPlaceholder(lines: 2, compact: true)
                            } else {
                                ProfileTextList(texts: profile.displayableContact, font: .subheadline)
                            }
                        }
                        SectionCard(title: "Statut et cursus") {
                            if profile.displayableStatus.isEmpty && profile.displayableCursus.isEmpty {
                                LoadingListPlaceholder(lines: 2, compact: true)
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    ProfileTextList(texts: profile.displayableStatus, font: .subheadline)
                                    ProfileTextList(texts: profile.displayableCursus, font: .subheadline)
                                }
                            }
                        }
                        SectionCard(title: "Points") {
                            ProfileTextList(texts: ["Wallet: \(profile.wallet) | Points: \(profile.correctionPoint)"], font: .subheadline)
                        }
                        SectionCard(title: "Coalitions") {
                            switch profileStore.coalitionsState {
                            case .loading:
                                LoadingListPlaceholder(lines: 2, compact: true)
                            case .failed:
                                RetryRow(title: "Impossible de charger les coalitions") { profileStore.retryCoalitions() }
                            default:
                                if profile.displayableCoalitions.isEmpty {
                                    EmptyRow(text: "Aucune coalition")
                                } else {
                                    ProfileTextList(texts: profile.displayableCoalitions)
                                }
                            }
                        }
                        SectionCard(title: "Succès") {
                            if profile.displayableAchievements.isEmpty {
                                EmptyRow(text: "Aucun succès")
                            } else {
                                ProfileTextList(texts: profile.displayableAchievements)
                            }
                        }
                        SectionCard(title: "Projets terminés") {
                            switch profileStore.projectsState {
                            case .loading:
                                LoadingListPlaceholder(lines: 3)
                            case .failed:
                                RetryRow(title: "Impossible de charger les projets") { profileStore.retryProjects() }
                            default:
                                if profile.displayableFinishedProjects.isEmpty {
                                    EmptyRow(text: "Aucun projet terminé")
                                } else {
                                    ProfileTextList(texts: profile.displayableFinishedProjects)
                                }
                            }
                        }
                        SectionCard(title: "Projets en cours") {
                            switch profileStore.projectsState {
                            case .loading:
                                LoadingListPlaceholder(lines: 2)
                            case .failed:
                                RetryRow(title: "Impossible de charger les projets") { profileStore.retryProjects() }
                            default:
                                if profile.displayableActiveProjects.isEmpty {
                                    EmptyRow(text: "Aucun projet en cours")
                                } else {
                                    ProfileTextList(texts: profile.displayableActiveProjects)
                                }
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
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        VStack(alignment: .leading, spacing: 6) {
            ForEach(texts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, id: \.self) { text in
                Text(text).font(font)
            }
        }
    }
}

struct LoadingListPlaceholder: View {
    let lines: Int
    var compact: Bool = false
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            ForEach(0..<lines, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 8)
                    .fill(.gray.opacity(0.3))
                    .frame(height: compact ? 10 : 14)
                    .redacted(reason: .placeholder)
            }
        }
    }
}

struct RetryRow: View {
    let title: String
    let action: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(title)
                .font(.subheadline)
            Spacer()
            Button("Réessayer", action: action)
        }
    }
}

struct EmptyRow: View {
    let text: String
    var body: some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary)
    }
}
