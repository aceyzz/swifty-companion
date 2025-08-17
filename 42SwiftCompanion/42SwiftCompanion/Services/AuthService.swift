import Foundation
import AuthenticationServices
import Security
import SwiftUI

final class AuthService: NSObject, ObservableObject {
	static let shared = AuthService()
	@Published var isAuthenticated = false

	private let service = "intra.42.fr"
	private let accessAccount = "accessToken"
	private let refreshAccount = "refreshToken"
	private let expirationKey = "tokenExpiration"
	private let userLoginKey = "userLogin"
	private var session: ASWebAuthenticationSession?
	private var refresher: TokenRefresher?
	private var tokenUrl: String { "https://api.intra.42.fr/oauth/token" }
	private var authorizeUrl: String { "https://api.intra.42.fr/oauth/authorize" }
	private var clientId: String { APIConfig.clientId }
	private var clientSecret: String { APIConfig.clientSecret }
	private var redirectUri: String { APIConfig.redirectUri }

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
			refresher = TokenRefresher(authService: self)
			refresher?.start()
		} else {
			isAuthenticated = false
			refresher?.invalidate()
		}
	}

	func login() {
		guard let scheme = URL(string: redirectUri)?.scheme else { return }
		guard let authURL = URL(string: "\(authorizeUrl)?client_id=\(clientId)&redirect_uri=\(redirectUri)&response_type=code") else { return }
		session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: scheme) { [weak self] callbackURL, error in
			guard let self = self, let url = callbackURL, error == nil else { return }
			guard let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value else { return }
			Task { await self.fetchToken(code: code) }
		}
		session?.presentationContextProvider = self
		session?.start()
	}

	@MainActor
	private func fetchToken(code: String) async {
		guard let url = URL(string: tokenUrl) else { return }
		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		let body = "grant_type=authorization_code&client_id=\(clientId)&client_secret=\(clientSecret)&code=\(code)&redirect_uri=\(redirectUri)"
		request.httpBody = body.data(using: .utf8)
		request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
		do {
			let (data, _) = try await URLSession.shared.data(for: request)
			if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
				if let access = json["access_token"] as? String,
				   let refresh = json["refresh_token"] as? String,
				   let expires = json["expires_in"] as? Double {
					self.accessToken = access
					self.refreshToken = refresh
					self.tokenExpiration = Date().addingTimeInterval(expires)
					self.isAuthenticated = true
					await fetchAndStoreCurrentUserLogin()
					refresher = TokenRefresher(authService: self)
					refresher?.start()
				}
			}
		} catch {
			self.isAuthenticated = false
		}
	}

	@MainActor
	private func fetchAndStoreCurrentUserLogin() async {
		guard let token = self.accessToken else { return }
		guard let url = URL(string: "https://api.intra.42.fr/v2/me") else { return }
		var request = URLRequest(url: url)
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		do {
			let (data, _) = try await URLSession.shared.data(for: request)
			if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let login = json["login"] as? String {
				setCurrentUserLogin(login)
			}
		} catch {}
	}

	func refreshAccessToken(completion: (() -> Void)? = nil) {
		guard let refresh = refreshToken, let url = URL(string: tokenUrl) else { return }
		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		let body = "grant_type=refresh_token&client_id=\(clientId)&client_secret=\(clientSecret)&refresh_token=\(refresh)"
		request.httpBody = body.data(using: .utf8)
		request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
		URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
			guard let self = self, let data = data, error == nil else { return }
			if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			   let token = json["access_token"] as? String,
			   let expiresIn = json["expires_in"] as? Double {
				DispatchQueue.main.async {
					self.accessToken = token
					self.tokenExpiration = Date().addingTimeInterval(expiresIn)
					if let refresh = json["refresh_token"] as? String {
						self.refreshToken = refresh
					}
					completion?()
				}
			}
		}.resume()
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

enum KeychainHelper {
	static func set(_ value: String, service: String, account: String) {
		guard let data = value.data(using: .utf8) else { return }
		let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
									kSecAttrService as String: service,
									kSecAttrAccount as String: account]
		SecItemDelete(query as CFDictionary)
		let attributes: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
										 kSecAttrService as String: service,
										 kSecAttrAccount as String: account,
										 kSecValueData as String: data]
		SecItemAdd(attributes as CFDictionary, nil)
	}

	static func get(service: String, account: String) -> String? {
		let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
									kSecAttrService as String: service,
									kSecAttrAccount as String: account,
									kSecReturnData as String: true,
									kSecMatchLimit as String: kSecMatchLimitOne]
		var dataTypeRef: AnyObject?
		let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
		guard status == errSecSuccess, let data = dataTypeRef as? Data else { return nil }
		return String(data: data, encoding: .utf8)
	}

	static func delete(service: String, account: String) {
		let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
									kSecAttrService as String: service,
									kSecAttrAccount as String: account]
		SecItemDelete(query as CFDictionary)
	}
}

final class TokenRefresher {
	private weak var authService: AuthService?
	private var timer: Timer?

	init(authService: AuthService) {
		self.authService = authService
	}

	func start() {
		timer?.invalidate()
		schedule()
	}

	func invalidate() {
		timer?.invalidate()
		timer = nil
	}

	private func schedule() {
		guard let expiration = authService?.tokenExpiration else { return }
		let interval = max(expiration.timeIntervalSinceNow - 60, 10)
		timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
			self?.refresh()
		}
	}

	private func refresh() {
		authService?.refreshAccessToken { [weak self] in
			self?.schedule()
		}
	}

	deinit {
		timer?.invalidate()
	}
}
