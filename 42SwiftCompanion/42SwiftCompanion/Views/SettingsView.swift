import SwiftUI

struct SettingsView: View {
    @ObservedObject var authService = AuthService.shared
    var body: some View {
        VStack {
            Text("Réglages")
                .font(.largeTitle)
                .frame(maxWidth: .infinity)
            Spacer()
            Button(action: {
                LogoutService.shared.logout()
            }) {
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
