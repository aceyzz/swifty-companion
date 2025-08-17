import Foundation

protocol NetworkServiceProtocol {
    func request<T: Decodable>(_ urlRequest: URLRequest, as type: T.Type) async throws -> T
}

final class NetworkService: NetworkServiceProtocol {
    static let shared = NetworkService()
    private let urlSession: URLSession

    init(session: URLSession = .shared) {
        self.urlSession = session
    }

    func request<T: Decodable>(_ urlRequest: URLRequest, as type: T.Type) async throws -> T {
        let (data, response) = try await urlSession.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.invalidResponse
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw NetworkError.decoding(error)
        }
    }
}

enum NetworkError: Error {
    case invalidResponse
    case decoding(Error)
}
