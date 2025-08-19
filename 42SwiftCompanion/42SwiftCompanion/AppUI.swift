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
                        .environmentObject(profileStore)
                }
            }
            .onAppear {
                authService.checkAuthentication()
                if authService.isAuthenticated { profileStore.start() }
            }
            .onChange(of: authService.isAuthenticated) {
                if authService.isAuthenticated {
                    profileStore.start()
                } else {
                    profileStore.stop()
                }
            }
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Image(systemName: "house.fill"); Text("Accueil") }
            SearchView()
                .tabItem { Image(systemName: "magnifyingglass"); Text("Recherche") }
            MyProfileView()
                .tabItem { Image(systemName: "person.crop.circle"); Text("Profil") }
            SettingsView()
                .tabItem { Image(systemName: "gearshape.fill"); Text("Réglages") }
        }
    }
}

struct HomeView: View {
    var body: some View {
        Text("Accueil")
            .font(.largeTitle)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SearchView: View {
    var body: some View {
        Text("Recherche étudiant")
            .font(.largeTitle)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                Text("Login via 42")
                    .font(.title2)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(10)
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
            Text("Réglages")
                .font(.largeTitle)
                .frame(maxWidth: .infinity)
            Spacer()
            Button {
                authService.logout()
            } label: {
                Text("Se déconnecter")
                    .font(.title2)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
