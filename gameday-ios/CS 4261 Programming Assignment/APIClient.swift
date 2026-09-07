//
//  APIClient.swift
//  CS 4261 Programming Assignment
//
//  Created by Sam Heseltine on 9/6/26.
//

import Foundation

enum APIError: Error {
    case badResponse(Int)
}

struct APIClient {
    static let baseURL = "https://cs4261-programming-assignment.onrender.com"

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

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

        let (data, response) = try await URLSession.shared.data(from: components.url!)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.badResponse((response as? HTTPURLResponse)?.statusCode ?? -1)
        }

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

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.badResponse((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
    }
}

