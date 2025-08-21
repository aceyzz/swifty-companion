import SwiftUI

@main
struct _2SwiftCompanionApp: App {
    @StateObject private var authService = AuthService.shared
    @StateObject private var profileStore = ProfileStore.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if authService.isAuthenticated {
                    MainTabView()
                        .environmentObject(authService)
                        .environmentObject(profileStore)
                } else {
                    LoginView()
                        .environmentObject(authService)
                }
            }
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
            .animation(.snappy, value: authService.isPostWebAuthLoading)
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView().tabItem { Image(systemName: "house.fill"); Text("Accueil") }
            SearchView().tabItem { Image(systemName: "magnifyingglass"); Text("Recherche") }
            MyProfileView().tabItem { Image(systemName: "person.crop.circle"); Text("Profil") }
            SettingsView().tabItem { Image(systemName: "gearshape.fill"); Text("Réglages") }
        }
    }
}

struct HomeView: View {
    var body: some View {
        Text("Accueil").font(.largeTitle).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SearchView: View {
    var body: some View {
        Text("Recherche étudiant").font(.largeTitle).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LoginView: View {
    @EnvironmentObject var authService: AuthService
    var body: some View {
        VStack {
            Spacer()
            Button {
                authService.login()
            } label: {
                Text("Login via 42").font(.title2).padding().frame(maxWidth: .infinity).background(Color.accentColor).foregroundColor(.white).cornerRadius(10)
            }
            .padding(.horizontal, 40)
            Spacer()
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var authService: AuthService
    var body: some View {
        VStack {
            Text("Réglages").font(.largeTitle).frame(maxWidth: .infinity)
            Spacer()
            Button {
                authService.logout()
            } label: {
                Text("Se déconnecter").font(.title2).padding().frame(maxWidth: .infinity).background(Color.red).foregroundColor(.white).cornerRadius(10)
            }
            .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
