import Foundation
import AuthenticationServices
import Security
import SwiftUI
import UIKit

struct APIConfig {
    static var clientId: String { Bundle.main.object(forInfoDictionaryKey: "API_CLIENT_ID") as? String ?? "" }
    static var clientSecret: String { Bundle.main.object(forInfoDictionaryKey: "API_CLIENT_SECRET") as? String ?? "" }
    static var redirectUri: String { Bundle.main.object(forInfoDictionaryKey: "API_REDIRECT_URI") as? String ?? "" }
}

enum KeychainHelper {
    static func set(_ value: String, service: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        let attributes: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecValueData as String: data]
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func get(service: String, account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        guard status == errSecSuccess, let data = dataTypeRef as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(service: String, account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }
}

private struct TokenResponse: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Double
}

private struct MeLogin: Decodable {
    let login: String
}

@MainActor
final class AuthService: NSObject, ObservableObject {
    enum Phase: Equatable { case unknown, unauthenticated, authenticated }

    static let shared = AuthService()

    @Published private(set) var isAuthenticated = false
    @Published private(set) var currentLogin: String = ""
    @Published private(set) var isPostWebAuthLoading = false
    @Published private(set) var phase: Phase = .unknown

    private let service = "intra.42.fr"
    private let accessAccount = "accessToken"
    private let refreshAccount = "refreshToken"
    private let expirationKey = "tokenExpiration"
    private let userLoginKey = "userLogin"

    private var session: ASWebAuthenticationSession?
    private var refreshTask: Task<Void, Never>?

    private var tokenUrl: String { "https://api.intra.42.fr/oauth/token" }
    private var authorizeUrl: String { "https://api.intra.42.fr/oauth/authorize" }

    override private init() {
        super.init()
        currentLogin = UserDefaults.standard.string(forKey: userLoginKey) ?? ""
    }

    var accessToken: String? {
        get { KeychainHelper.get(service: service, account: accessAccount) }
        set {
            if let value = newValue { KeychainHelper.set(value, service: service, account: accessAccount) }
            else { KeychainHelper.delete(service: service, account: accessAccount) }
        }
    }

    var refreshToken: String? {
        get { KeychainHelper.get(service: service, account: refreshAccount) }
        set {
            if let value = newValue { KeychainHelper.set(value, service: service, account: refreshAccount) }
            else { KeychainHelper.delete(service: service, account: refreshAccount) }
        }
    }

    var tokenExpiration: Date? {
        get {
            guard let interval = UserDefaults.standard.object(forKey: expirationKey) as? TimeInterval else { return nil }
            return Date(timeIntervalSince1970: interval)
        }
        set {
            if let date = newValue { UserDefaults.standard.set(date.timeIntervalSince1970, forKey: expirationKey) }
            else { UserDefaults.standard.removeObject(forKey: expirationKey) }
        }
    }

    func getCurrentUserLogin() -> String { currentLogin }

    private func setCurrentUserLogin(_ login: String) {
        currentLogin = login
        UserDefaults.standard.set(login, forKey: userLoginKey)
    }

    func checkAuthentication() {
        phase = .unknown
        if let token = accessToken, let expiration = tokenExpiration, expiration > Date(), !token.isEmpty {
            isAuthenticated = true
            phase = .authenticated
            Task {
                await startRefreshLoop()
                if currentLogin.isEmpty { await fetchAndStoreCurrentUserLogin() }
            }
        } else {
            isAuthenticated = false
            phase = .unauthenticated
            cancelRefreshLoop()
        }
    }

    func login() {
        guard let scheme = URL(string: APIConfig.redirectUri)?.scheme else { return }
        guard let authURL = URL(string: "\(authorizeUrl)?client_id=\(APIConfig.clientId)&redirect_uri=\(APIConfig.redirectUri)&response_type=code") else { return }
        session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: scheme) { [weak self] callbackURL, error in
            guard let self else { return }
            if error != nil { self.isPostWebAuthLoading = false; return }
            guard let url = callbackURL else { self.isPostWebAuthLoading = false; return }
            guard let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value else { self.isPostWebAuthLoading = false; return }
            self.isPostWebAuthLoading = true
            Task {
                defer { self.isPostWebAuthLoading = false }
                await self.exchangeCodeForTokens(code: code)
            }
        }
        session?.prefersEphemeralWebBrowserSession = true
        session?.presentationContextProvider = self
        session?.start()
    }

    func logout() {
        accessToken = nil
        refreshToken = nil
        tokenExpiration = nil
        currentLogin = ""
        isAuthenticated = false
        isPostWebAuthLoading = false
        phase = .unauthenticated
        UserDefaults.standard.removeObject(forKey: userLoginKey)
        cancelRefreshLoop()
        ProfileStore.shared.stop()
        session = nil
    }

    private func startRefreshLoop() async {
        cancelRefreshLoop()
        guard let expiration = tokenExpiration else { return }
        let interval = max(expiration.timeIntervalSinceNow - 60, 10)
        refreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard let self else { return }
            if Task.isCancelled { return }
            await self.refreshAccessToken()
            await self.startRefreshLoop()
        }
    }

    private func cancelRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func updateTokens(_ t: TokenResponse) {
        accessToken = t.access_token
        if let r = t.refresh_token { refreshToken = r }
        tokenExpiration = Date().addingTimeInterval(t.expires_in)
        isAuthenticated = true
        phase = .authenticated
    }

    private func exchangeCodeForTokens(code: String) async {
        guard let url = URL(string: tokenUrl) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let body = "grant_type=authorization_code&client_id=\(APIConfig.clientId)&client_secret=\(APIConfig.clientSecret)&code=\(code)&redirect_uri=\(APIConfig.redirectUri)"
        request.httpBody = body.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let tokens = try? JSONDecoder().decode(TokenResponse.self, from: data) {
                updateTokens(tokens)
                await fetchAndStoreCurrentUserLogin()
                await startRefreshLoop()
            } else {
                isAuthenticated = false
                phase = .unauthenticated
            }
        } catch {
            isAuthenticated = false
            phase = .unauthenticated
        }
    }

    private func fetchAndStoreCurrentUserLogin() async {
        do {
            let me: MeLogin = try await APIClient.shared.request(Endpoint(path: "/v2/me"), as: MeLogin.self)
            setCurrentUserLogin(me.login)
            ProfileStore.shared.start(for: me.login)
        } catch {}
    }

    func refreshAccessToken() async {
        guard let refresh = refreshToken, let url = URL(string: tokenUrl) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let body = "grant_type=refresh_token&client_id=\(APIConfig.clientId)&client_secret=\(APIConfig.clientSecret)&refresh_token=\(refresh)"
        request.httpBody = body.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let tokens = try? JSONDecoder().decode(TokenResponse.self, from: data) {
                updateTokens(tokens)
            } else {
                isAuthenticated = false
                phase = .unauthenticated
            }
        } catch {
            isAuthenticated = false
            phase = .unauthenticated
        }
    }
}

extension AuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            return scene.windows.first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
        return ASPresentationAnchor()
    }
}
