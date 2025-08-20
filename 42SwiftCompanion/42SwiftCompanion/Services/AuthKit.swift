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
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func get(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        guard status == errSecSuccess, let data = dataTypeRef as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

@MainActor
final class AuthService: NSObject, ObservableObject {
    static let shared = AuthService()

    @Published private(set) var isAuthenticated = false

    private let service = "intra.42.fr"
    private let accessAccount = "accessToken"
    private let refreshAccount = "refreshToken"
    private let expirationKey = "tokenExpiration"
    private let userLoginKey = "userLogin"

    private var session: ASWebAuthenticationSession?
    private var refreshTask: Task<Void, Never>?

    private var tokenUrl: String { "https://api.intra.42.fr/oauth/token" }
    private var authorizeUrl: String { "https://api.intra.42.fr/oauth/authorize" }

    var accessToken: String? {
        get { KeychainHelper.get(service: service, account: accessAccount) }
        set {
            if let value = newValue {
                KeychainHelper.set(value, service: service, account: accessAccount)
            } else {
                KeychainHelper.delete(service: service, account: accessAccount)
            }
        }
    }

    var refreshToken: String? {
        get { KeychainHelper.get(service: service, account: refreshAccount) }
        set {
            if let value = newValue {
                KeychainHelper.set(value, service: service, account: refreshAccount)
            } else {
                KeychainHelper.delete(service: service, account: refreshAccount)
            }
        }
    }

    var tokenExpiration: Date? {
        get {
            guard let interval = UserDefaults.standard.object(forKey: expirationKey) as? TimeInterval else { return nil }
            return Date(timeIntervalSince1970: interval)
        }
        set {
            if let date = newValue {
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: expirationKey)
            } else {
                UserDefaults.standard.removeObject(forKey: expirationKey)
            }
        }
    }

    func getCurrentUserLogin() -> String {
        UserDefaults.standard.string(forKey: userLoginKey) ?? ""
    }

    private func setCurrentUserLogin(_ login: String) {
        UserDefaults.standard.set(login, forKey: userLoginKey)
    }

    func checkAuthentication() {
        if let token = accessToken, let expiration = tokenExpiration, expiration > Date(), !token.isEmpty {
            isAuthenticated = true
            Task {
                await self.startRefreshLoop()
                if self.getCurrentUserLogin().isEmpty { await self.fetchAndStoreCurrentUserLogin() }
            }
        } else {
            isAuthenticated = false
            cancelRefreshLoop()
        }
    }

    func login() {
        guard let scheme = URL(string: APIConfig.redirectUri)?.scheme else { return }
        guard let authURL = URL(string: "\(authorizeUrl)?client_id=\(APIConfig.clientId)&redirect_uri=\(APIConfig.redirectUri)&response_type=code") else { return }
        session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: scheme) { [weak self] callbackURL, error in
            guard let self, let url = callbackURL, error == nil else { return }
            guard let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value else { return }
            Task { await self.exchangeCodeForTokens(code: code) }
        }
        session?.presentationContextProvider = self
        session?.start()
    }

    func logout() {
        accessToken = nil
        refreshToken = nil
        tokenExpiration = nil
        isAuthenticated = false
        UserDefaults.standard.removeObject(forKey: userLoginKey)
        cancelRefreshLoop()
        ProfileStore.shared.stop()
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

    private func exchangeCodeForTokens(code: String) async {
        guard let url = URL(string: tokenUrl) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let body = "grant_type=authorization_code&client_id=\(APIConfig.clientId)&client_secret=\(APIConfig.clientSecret)&code=\(code)&redirect_uri=\(APIConfig.redirectUri)"
        request.httpBody = body.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let access = json["access_token"] as? String,
                   let refresh = json["refresh_token"] as? String,
                   let expires = json["expires_in"] as? Double {
                    accessToken = access
                    refreshToken = refresh
                    tokenExpiration = Date().addingTimeInterval(expires)
                    isAuthenticated = true
                    await fetchAndStoreCurrentUserLogin()
                    await startRefreshLoop()
                }
            }
        } catch {
            isAuthenticated = false
        }
    }

    private func fetchAndStoreCurrentUserLogin() async {
        guard let token = accessToken else { return }
        guard let url = URL(string: "https://api.intra.42.fr/v2/me") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let login = json["login"] as? String {
                setCurrentUserLogin(login)
            }
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
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let token = json["access_token"] as? String,
               let expiresIn = json["expires_in"] as? Double {
                accessToken = token
                tokenExpiration = Date().addingTimeInterval(expiresIn)
                if let newRefresh = json["refresh_token"] as? String {
                    refreshToken = newRefresh
                }
                isAuthenticated = true
            }
        } catch {
            isAuthenticated = false
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
