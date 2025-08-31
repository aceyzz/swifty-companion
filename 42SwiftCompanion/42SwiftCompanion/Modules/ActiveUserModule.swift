import SwiftUI
import Foundation

struct ActiveUsersSheet: View {
    @Environment(\.dismiss) private var dismiss
    let campusId: Int

    @State private var state: LoadState = .loading
    @State private var users: [CampusActiveUser] = []
    @State private var lastError: String?

    enum LoadState { case loading, loaded, failed }

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .loading:
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Chargement…").font(.footnote).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                case .failed:
                    VStack(spacing: 12) {
                        Text(lastError ?? "Erreur inconnue").font(.callout)
                        Button("Réessayer") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                case .loaded:
                    if users.isEmpty {
                        ContentUnavailableView("Aucun utilisateur connecté", systemImage: "wifi.exclamationmark")
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                ForEach(users) { u in
                                    ActiveUserRow(user: u)
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            .navigationTitle("Connectés maintenant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await load() }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .accessibilityLabel("Rafraîchir")
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        state = .loading
        do {
            users = try await CampusRepository.shared.activeUsers(campusId: campusId)
            state = .loaded
        } catch {
            lastError = "Impossible de charger la liste"
            state = .failed
        }
    }
}

private struct ActiveUserRow: View {
    let user: CampusActiveUser

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: user.imageURL) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                case .empty: ProgressView()
                case .failure: Image(systemName: "person.crop.circle.fill").resizable().scaledToFill()
                @unknown default: Image(systemName: "person.crop.circle.fill").resizable().scaledToFill()
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(user.login).font(.callout.weight(.semibold))
                Text(user.host ?? "Poste inconnu").font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}
