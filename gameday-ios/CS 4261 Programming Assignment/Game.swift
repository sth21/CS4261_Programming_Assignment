//
//  Game.swift
//  CS 4261 Programming Assignment
//
//  Created by Sam Heseltine on 9/6/26.
//

import Foundation

struct Game: Codable, Identifiable {
    let cfbdId: Int
    let season: Int
    let week: Int
    let homeTeam: String
    let awayTeam: String
    let homeId: Int?
    let awayId: Int?
    let homeConference: String?
    let awayConference: String?
    let startDate: Date
    let completed: Bool
    let homePoints: Int?
    let awayPoints: Int?
    let venue: String?
    let lastSyncedAt: Date
    
    var id: Int { cfbdId }
    
    enum CodingKeys: String, CodingKey {
        case cfbdId = "cfbd_id"
        case season, week, completed, venue
        case homeTeam = "home_team"
        case awayTeam = "away_team"
        case homeId = "home_id"
        case awayId = "away_id"
        case homeConference = "home_conference"
        case awayConference = "away_conference"
        case startDate = "start_date"
        case homePoints = "home_points"
        case awayPoints = "away_points"
        case lastSyncedAt = "last_synced_at"
    }
}
