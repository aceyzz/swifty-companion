import SwiftUI

struct LoginView: View {
    @ObservedObject var authService = AuthService.shared
    var body: some View {
        VStack {
            Spacer()
            Button(action: {
                authService.login()
            }) {
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
