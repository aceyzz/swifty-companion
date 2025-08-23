import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authService: AuthService
    @State private var hapticTick = false

    var body: some View {
        ZStack {
            RadialGradient(colors: [.accentColor.opacity(0.22), .clear], center: .center, startRadius: 0, endRadius: 500)
                .ignoresSafeArea()
            VStack {
                Spacer()
                VStack(spacing: 16) {
                    Text(appName).font(.largeTitle.bold())
                    Text("Connecte-toi avec ton compte Intra 42 pour accéder à ton profil, tes projets et tes stats.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .contentShape(Rectangle())
                Spacer()
                VStack(spacing: 12) {
                    Button(action: {
                        hapticTick.toggle()
                        authService.login()
                    }) {
                        HStack(spacing: 12) {
                            AsyncImage(url: URL(string: "https://profile.intra.42.fr/assets/42_logo_black-684989d43d629b3c0ff6fd7e1157ee04db9bb7a73fba8ec4e01543d650a1c607.png")) { image in
                                image.resizable().scaledToFit().frame(width: 20, height: 20)
                            } placeholder: {
                                Color.white.opacity(0.2)
                            }
                            .frame(width: 28, height: 28)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white))
                            Text(authService.isPostWebAuthLoading ? "Connexion…" : "Se connecter avec 42").font(.headline)
                            Spacer()
                            if authService.isPostWebAuthLoading {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.right").font(.headline)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.black))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(authService.isPostWebAuthLoading)
                    .sensoryFeedback(.impact, trigger: hapticTick)
                    .accessibilityLabel(Text("Se connecter avec 42"))
                    .accessibilityHint(Text("Ouvre la page d’authentification 42"))
                    Text("Tu seras redirigé vers l’Intranet 42 pour t’identifier.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 100)
            }
        }
    }

    private var appName: String {
        if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, !name.isEmpty { return name }
        if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String, !name.isEmpty { return name }
        return "App"
    }
}
