import Foundation

nonisolated enum Config {
    static let baseURL = URL(string: "https://nfl.schnetz.us")!
}

nonisolated enum APIError: Error, LocalizedError {
    case badResponse
    case status(Int)
    case decoding(any Error)

    var errorDescription: String? {
        switch self {
        case .badResponse: "Network error"
        case .status(let code): "Server returned \(code)"
        case .decoding(let err): "Decoding failed: \(err.localizedDescription)"
        }
    }
}

actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let baseURL: URL
    private let decoder: JSONDecoder

    init(session: URLSession = .shared, baseURL: URL = Config.baseURL) {
        self.session = session
        self.baseURL = baseURL
        self.decoder = JSONDecoder.nflBackend
    }

    func get<T: Decodable & Sendable>(_ path: String, as _: T.Type = T.self) async throws -> T {
        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.badResponse }
        guard (200..<300).contains(http.statusCode) else { throw APIError.status(http.statusCode) }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }
}

extension JSONDecoder {
    nonisolated static let nflBackend: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)

            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)

            // ESPN passthrough emits "2026-02-08T23:30Z"; nflverse routes use full ISO8601.
            for pattern in ["yyyy-MM-dd'T'HH:mm'Z'",
                            "yyyy-MM-dd'T'HH:mm:ssZ",
                            "yyyy-MM-dd'T'HH:mm:ss.SSSZ"] {
                formatter.dateFormat = pattern
                if let date = formatter.date(from: raw) { return date }
            }
            throw DecodingError.dataCorruptedError(in: container,
                                                   debugDescription: "Unrecognized date: \(raw)")
        }
        return decoder
    }()
}
