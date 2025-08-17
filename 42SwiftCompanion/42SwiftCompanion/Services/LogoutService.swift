import Foundation

class LogoutService {
    static let shared = LogoutService()
    private init() {}

    func logout() {
        AuthService.shared.accessToken = nil
        AuthService.shared.refreshToken = nil
        AuthService.shared.isAuthenticated = false
        UserDefaults.standard.removeObject(forKey: "tokenExpiration")
        UserDefaults.standard.removeObject(forKey: "userLogin")
    }
}
