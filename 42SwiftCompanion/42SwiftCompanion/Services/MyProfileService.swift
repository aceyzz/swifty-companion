import Foundation

final class MyProfileService {
    static let shared = MyProfileService()
    private init() {}

    func fetchMyProfile() async throws -> UserProfile {
        let login = AuthService.shared.getCurrentUserLogin()
        guard !login.isEmpty else { throw URLError(.userAuthenticationRequired) }
        return try await UserService.shared.fetchFullProfile(login: login)
    }
}
