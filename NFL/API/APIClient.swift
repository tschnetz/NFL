import Foundation

nonisolated enum Config {
    static let baseURL = URL(string: "https://nfl.schnetz.us")!
}

nonisolated enum APIError: Error, LocalizedError {
    case badResponse
    case status(Int)
    case server(String)
    case decoding(any Error)

    var errorDescription: String? {
        switch self {
        case .badResponse: "Network error"
        case .status(let code): "Server returned \(code)"
        case .server(let message): message
        case .decoding(let err): "Decoding failed: \(err.localizedDescription)"
        }
    }
}

actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let baseURL: URL
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private var authToken: String?

    init(session: URLSession = .shared, baseURL: URL = Config.baseURL) {
        self.session = session
        self.baseURL = baseURL
        self.decoder = JSONDecoder.nflBackend
        self.encoder = JSONEncoder()
    }

    func setAuthToken(_ token: String?) {
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.authToken = (trimmed?.isEmpty == false) ? trimmed : nil
    }

    func get<T: Decodable & Sendable>(
        _ path: String,
        queryItems: [URLQueryItem] = [],
        as _: T.Type = T.self
    ) async throws -> T {
        var components = URLComponents(url: baseURL.appending(path: path),
                                       resolvingAgainstBaseURL: false)!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else { throw APIError.badResponse }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    func post<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        _ path: String,
        body: Body,
        as _: Response.Type = Response.self
    ) async throws -> Response {
        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            // FastAPI emits `{"detail": ...}` on 4xx; for picks mutations,
            // `detail` is `{"ok": false, "error": "<message>"}`.
            if let parsed = parseErrorMessage(from: data) {
                throw APIError.server(parsed)
            }
            throw APIError.status(http.statusCode)
        }
    }

    private static func parseErrorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let detail = object["detail"] as? [String: Any], let err = detail["error"] as? String {
            return err
        }
        if let detail = object["detail"] as? String { return detail }
        if let err = object["error"] as? String { return err }
        return nil
    }
}

extension JSONDecoder {
    nonisolated static let nflBackend: JSONDecoder = {
        // Patterns the backend emits across routers:
        //   ESPN passthrough:  "2026-02-08T23:30Z"
        //   nflverse schedule: "2024-09-05T20:20:00+00:00"
        //   picks/admin:       "2026-05-14T16:32:05.994319Z"
        let patterns = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm'Z'",
        ]

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)

            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            for pattern in patterns {
                formatter.dateFormat = pattern
                if let date = formatter.date(from: raw) { return date }
            }
            throw DecodingError.dataCorruptedError(in: container,
                                                   debugDescription: "Unrecognized date: \(raw)")
        }
        return decoder
    }()
}
