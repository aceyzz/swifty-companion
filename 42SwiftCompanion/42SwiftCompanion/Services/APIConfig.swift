import Foundation

struct APIConfig {
    static var clientId: String {
        Bundle.main.object(forInfoDictionaryKey: "API_CLIENT_ID") as? String ?? ""
    }
    static var clientSecret: String {
        Bundle.main.object(forInfoDictionaryKey: "API_CLIENT_SECRET") as? String ?? ""
    }
    static var redirectUri: String {
        Bundle.main.object(forInfoDictionaryKey: "API_REDIRECT_URI") as? String ?? ""
    }
}
