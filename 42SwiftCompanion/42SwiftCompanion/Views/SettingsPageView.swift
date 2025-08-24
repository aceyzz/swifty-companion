import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authService: AuthService
	@EnvironmentObject var theme: Theme
    @State private var showLogoutConfirm = false
    @State private var tick = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Paramètres")
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                LazyVStack(spacing: 24) {
                    SectionCard(title: "Compte") {
                        VStack(alignment: .leading, spacing: 10) {
                            InfoPillRow(
                                leading: .system("person.crop.circle.fill"),
                                title: displayLogin,
                                subtitle: "Connecté",
                                badges: [],
                                onTap: nil,
                                iconTint: nil
                            )
                            if let exp = authService.tokenExpiration {
                                InfoPillRow(
                                    leading: .system("lock.shield.fill"),
                                    title: "Jeton valide",
                                    subtitle: exp.formatted(date: .abbreviated, time: .shortened),
                                    badges: [],
                                    onTap: nil,
                                    iconTint: .green
                                )
                            } else {
                                InfoPillRow(
                                    leading: .system("lock.slash.fill"),
                                    title: "Jeton non disponible",
                                    subtitle: "Connecte-toi pour générer un jeton",
                                    badges: [],
                                    onTap: nil,
                                    iconTint: .orange
                                )
                            }
                        }
                    }

					SectionCard(title: "Application") {
						VStack(alignment: .leading, spacing: 10) {
							InfoPillRow(
								leading: .system("app.badge.fill"),
								title: appName,
								subtitle: "Version \(appVersion)",
								badges: [],
								onTap: nil,
								iconTint: nil
							)
							if let bundle = Bundle.main.bundleIdentifier {
								InfoPillRow(
									leading: .system("chevron.left.forwardslash.chevron.right"),
									title: "Identifiant du bundle",
									subtitle: bundle,
									badges: [],
									onTap: nil,
									iconTint: nil
								)
							}
							InfoPillRow(
								leading: .system("exclamationmark.bubble.fill"),
								title: "Soumettre un bug",
								subtitle: nil,
								badges: [],
                                onTap: {
                                    let encoded = "cedmulle@student.42lausanne.ch".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
                                    if let encoded, let url = URL(string: "mailto:\(encoded)") {
                                        UIApplication.shared.open(url)
                                    }
                                },
								iconTint: nil
							)
						}
					}

                    SectionCard(title: "Session") {
                        VStack(spacing: 12) {
                            Button {
                                tick.toggle()
                                showLogoutConfirm = true
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "rectangle.portrait.and.arrow.right").font(.headline)
                                    Text("Se déconnecter").font(.headline)
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .frame(maxWidth: .infinity)
                                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.red))
                                .foregroundStyle(.white)
                            }
                            .buttonStyle(PressableScaleStyle())
                            .sensoryFeedback(.impact, trigger: tick)
                            .accessibilityLabel(Text("Se déconnecter"))
                            .accessibilityHint(Text("Ferme la session actuelle"))
                            .confirmationDialog("Confirmer la déconnexion", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
                                Button("Se déconnecter", role: .destructive) { authService.logout() }
                                Button("Annuler", role: .cancel) {}
                            }
                        }
                    }

                    HStack {
                        Spacer()
                        Link(destination: URL(string: "https://profile.intra.42.fr/users/cedmulle")!) {
							HStack(spacing: 6) {
								Image(systemName: "person.crop.circle").font(.subheadline)
								Text("Créé par cedmulle").font(.footnote).foregroundStyle(.secondary)
								Image(systemName: "arrow.up.right.square")
									.font(.footnote)
									.foregroundStyle(theme.accentColor)
							}
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color(.systemGray6)))
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }
            .padding()
        }
    }

    private var displayLogin: String {
        let login = authService.getCurrentUserLogin()
        return login.isEmpty ? "Non connecté" : login
    }

    private var appName: String {
        if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, !name.isEmpty { return name }
        if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String, !name.isEmpty { return name }
        return "App"
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}

private struct PressableScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.92 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(duration: 0.18, bounce: 0.2), value: configuration.isPressed)
    }
}
