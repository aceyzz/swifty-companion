import SwiftUI

struct BlockingProgressOverlay: View {
    let title: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.2).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().controlSize(.large)
                Text(title).font(.callout).foregroundStyle(.primary)
            }
            .padding(20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(radius: 8)
        }
        .transition(.opacity)
    }
}

struct RetryRow: View {
    let title: String
    let action: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(title).font(.subheadline)
            Spacer()
            Button("Réessayer", action: action)
        }
    }
}

struct EmptyRow: View {
    let text: String
    var body: some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary)
    }
}

struct ErrorBanner: View {
    let text: String
    var body: some View {
        VStack {
            Text(text)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.vertical, 16)
                .padding(.horizontal, 20)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(.systemRed))
                        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
                )
                .allowsHitTesting(false)
                .accessibilityLabel("Erreur: \(text)")
                .padding(.top, 8)
                .padding(.horizontal, 12)
            Spacer()
        }
    }
}

func describeCreateFailure(begin: Date, end: Date, error: Error) -> String {

    func readable(from body: String?) -> String? {
        guard let body, let data = body.data(using: .utf8) else { return nil }
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let s = dict["error"] as? String { return s }
            if let s = dict["message"] as? String { return s }
            if let errs = dict["errors"] as? [String: Any], !errs.isEmpty {
                let parts = errs.flatMap { key, val -> [String] in
                    if let arr = val as? [String] { return arr.map { "\(key): \($0)" } }
                    if let s = val as? String { return ["\(key): \(s)"] }
                    return []
                }
                if !parts.isEmpty { return parts.joined(separator: "\n") }
            }
        }
        return body
    }

    switch error {
    case let apiErr as APIError:
        switch apiErr {
        case .unauthorized:
            return "Authentification requise. Réessaie après t’être reconnecté."
        case .rateLimited(_):
            return "Trop de requêtes. Réessaie dans quelques instants."
        case .http(let status, let body):
            let msg = readable(from: body)
            if let msg, !msg.isEmpty { return msg }
            if status == 422 { return "Paramètres invalides pour le slot." }
            if status == 403 { return "Tu n’as pas les droits pour créer un slot." }
            return "Erreur serveur (\(status))."
        case .decoding(_):
            return "Réponse invalide du serveur."
        case .transport(let e):
            switch e.code {
            case .notConnectedToInternet: return "Pas de connexion Internet."
            case .timedOut: return "Délai dépassé."
            default: return "Erreur réseau (\(e.code.rawValue))."
            }
        }
    default:
        let ns = error as NSError
        return "La création du slot a échoué. \(ns.localizedDescription)"
    }
}

func describeDeleteFailure(ids: [Int], error: Error) -> String {
    switch error {
    case let apiErr as APIError:
        switch apiErr {
        case .unauthorized:
            return "Authentification requise. Réessaie après t’être reconnecté."
        case .rateLimited:
            return "Trop de requêtes. Réessaie dans quelques instants."
        case .http(let status, let body):
            if status == 403 { return "Tu n’as pas les droits pour supprimer ce slot." }
            if status == 404 { return "Ce slot n’existe plus." }
            if status == 409 { return "Ce slot ne peut pas être supprimé." }
            if let body, !body.isEmpty { return body }
            return "Erreur serveur (\(status))."
        case .decoding:
            return "Réponse invalide du serveur."
        case .transport(let e):
            switch e.code {
            case .notConnectedToInternet: return "Pas de connexion Internet."
            case .timedOut: return "Délai dépassé."
            default: return "Erreur réseau (\(e.code.rawValue))."
            }
        }
    default:
        let ns = error as NSError
        return "La suppression a échoué. \(ns.localizedDescription)"
    }
}
