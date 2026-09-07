import Foundation

enum APIError: Error {
    case unauthorized
    case offline
    case server(Int)
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
        config.timeoutIntervalForRequest = 60
        return URLSession(configuration: config)
    }()

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
            throw APIError.offline
        }
    }

    struct TokenResponse: Codable {
        let accessToken: String
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
        }
    }

    struct WeekResponse: Codable {
        let week: Int
    }

    static func authenticate(username: String, password: String, register: Bool) async throws -> String {
        let path = register ? "/auth/register" : "/auth/login"
        var request = URLRequest(url: URL(string: baseURL + path)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["username": username, "password": password])

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.server(-1) }
            guard http.statusCode == 200 else { throw APIError.server(http.statusCode) }
            return try decoder.decode(TokenResponse.self, from: data).accessToken
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.offline
        }
    }

    static func fetchCurrentWeek(season: Int = 2026) async throws -> Int {
        let url = URL(string: "\(baseURL)/games/current-week?season=\(season)")!
        let data = try await send(URLRequest(url: url))
        return try decoder.decode(WeekResponse.self, from: data).week
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
        return try decoder.decode([Game].self, from: data)
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
}
