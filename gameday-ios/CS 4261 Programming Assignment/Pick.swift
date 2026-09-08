//
//  Pick.swift
//  CS 4261 Programming Assignment
//
//  Created by Sam Heseltine on 9/7/26.
//

import Foundation

struct Pick: Codable, Identifiable {
    let id: Int
    let userId: Int
    let gameId: Int
    let predictedWinner: String
    let isCorrect: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case gameId = "game_id"
        case predictedWinner = "predicted_winner"
        case isCorrect = "is_correct"
    }
}

struct Record: Codable {
    let wins: Int
    let losses: Int
    let pending: Int
}

struct PicksResponse: Codable {
    let picks: [Pick]
    let record: Record
}
