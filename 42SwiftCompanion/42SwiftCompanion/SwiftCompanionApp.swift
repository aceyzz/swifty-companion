import SwiftUI

@main
struct _2SwiftCompanionApp: App {
    @StateObject private var authService = AuthService.shared
    @StateObject private var profileStore = ProfileStore.shared
    @StateObject private var theme = Theme.shared

    var body: some Scene {
        WindowGroup {
            Group {
                switch authService.phase {
                case .unknown:
                    BootView()
                        .tint(Color("AccentColor"))
                case .authenticated:
                    MainTabView()
                        .environmentObject(authService)
                        .environmentObject(profileStore)
                        .environmentObject(theme)
                case .unauthenticated:
                    LoginView()
                        .environmentObject(authService)
                        .tint(Color("AccentColor"))
                }
            }
            .tint(theme.accentColor)
            .environmentObject(theme)
            .onAppear { authService.checkAuthentication() }
            .onChange(of: authService.isAuthenticated) { _, newValue in
                if newValue, !authService.currentLogin.isEmpty { profileStore.start(for: authService.currentLogin) }
                if !newValue { profileStore.stop() }
            }
            .onChange(of: authService.currentLogin) { _, login in
                if authService.isAuthenticated, !login.isEmpty { profileStore.start(for: login) }
            }
            .overlay {
                if authService.isPostWebAuthLoading {
                    BlockingProgressOverlay(title: "Connexion…")
                }
            }
            .disabled(authService.isPostWebAuthLoading)
            .animation(.snappy, value: authService.phase)
            .animation(.snappy, value: authService.isPostWebAuthLoading)
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView().tabItem { Image(systemName: "house.fill"); Text("Accueil") }
            SearchView().tabItem { Image(systemName: "magnifyingglass"); Text("Recherche") }
            SlotsPageView().tabItem { Image(systemName: "calendar.badge.clock"); Text("Slots") }
            MyProfileView().tabItem { Image(systemName: "person.crop.circle"); Text("Profil") }
            SettingsView().tabItem { Image(systemName: "gearshape.fill"); Text("Réglages") }
        }
    }
}
