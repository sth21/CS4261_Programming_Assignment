import Foundation

enum APIError: Error {
    case unauthorized
    case offline
    case server(Int)
    case decoding
}

struct PickBody: Encodable {
    let game_id: Int
    let predicted_winner: String
}

struct APIClient {
    static let baseURL = "https://cs4261-programming-assignment.onrender.com"

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 90
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }()

    static func normalized(_ error: Error) -> Error {
        if error is CancellationError { return CancellationError() }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return CancellationError()
        }
        return APIError.offline
    }

    static func send(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.server(-1)
            }
            if http.statusCode == 401 { throw APIError.unauthorized }
            guard (200..<300).contains(http.statusCode) else {
                throw APIError.server(http.statusCode)
            }
            return data
        } catch let error as APIError {
            throw error
        } catch {
            throw normalized(error)
        }
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw APIError.decoding
        }
    }

    static func authed(_ url: URL, method: String = "GET", token: String, body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    struct TokenResponse: Codable {
        let accessToken: String
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
        }
    }

    struct CurrentSlate: Codable {
        let week: Int
        let games: [Game]
    }

    static func authenticate(username: String, password: String, register: Bool) async throws -> String {
        let path = register ? "/auth/register" : "/auth/login"
        var request = URLRequest(url: URL(string: baseURL + path)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["username": username, "password": password])

        let data: Data
        do {
            let (body, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.server(-1) }
            guard http.statusCode == 200 else { throw APIError.server(http.statusCode) }
            data = body
        } catch let error as APIError {
            throw error
        } catch {
            throw normalized(error)
        }

        return try decode(TokenResponse.self, from: data).accessToken
    }

    static func fetchCurrentSlate(season: Int = 2026) async throws -> CurrentSlate {
        let url = URL(string: "\(baseURL)/games/current?season=\(season)")!
        let data = try await send(URLRequest(url: url))
        return try decode(CurrentSlate.self, from: data)
    }

    static func fetchGames(season: Int = 2026, week: Int, conference: String? = nil) async throws -> [Game] {
        var components = URLComponents(string: "\(baseURL)/games")!
        var items = [
            URLQueryItem(name: "season", value: String(season)),
            URLQueryItem(name: "week", value: String(week)),
        ]
        if let conference {
            items.append(URLQueryItem(name: "conference", value: conference))
        }
        components.queryItems = items

        let data = try await send(URLRequest(url: components.url!))
        return try decode([Game].self, from: data)
    }

    static func refreshGames(season: Int = 2026, week: Int) async throws {
        var components = URLComponents(string: "\(baseURL)/games/refresh")!
        components.queryItems = [
            URLQueryItem(name: "season", value: String(season)),
            URLQueryItem(name: "week", value: String(week)),
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        _ = try await send(request)
    }

    static func fetchPicks(token: String) async throws -> PicksResponse {
        let url = URL(string: "\(baseURL)/picks")!
        let data = try await send(authed(url, token: token))
        return try decode(PicksResponse.self, from: data)
    }

    static func submitPick(gameId: Int, winner: String, token: String) async throws -> Pick {
        let url = URL(string: "\(baseURL)/picks")!
        let body = try JSONEncoder().encode(PickBody(game_id: gameId, predicted_winner: winner))
        let data = try await send(authed(url, method: "POST", token: token, body: body))
        return try decode(Pick.self, from: data)
    }

    static func deletePick(gameId: Int, token: String) async throws {
        let url = URL(string: "\(baseURL)/picks/\(gameId)")!
        _ = try await send(authed(url, method: "DELETE", token: token))
    }

    static func gradePicks(token: String) async throws {
        let url = URL(string: "\(baseURL)/picks/grade")!
        _ = try await send(authed(url, method: "POST", token: token))
    }
}
