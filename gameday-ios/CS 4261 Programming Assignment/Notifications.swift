import Foundation
import UserNotifications
import SwiftUI

@Observable
class NotificationStore {
    private let key = "subscribedGames"
    private(set) var subscribed: Set<Int> = []

    init() {
        let ids = UserDefaults.standard.array(forKey: key) as? [Int] ?? []
        subscribed = Set(ids)
    }

    private func persist() {
        UserDefaults.standard.set(Array(subscribed), forKey: key)
    }

    func isSubscribed(_ gameId: Int) -> Bool {
        subscribed.contains(gameId)
    }

    func canSchedule(_ game: Game) -> Bool {
        game.startDate.addingTimeInterval(-3600) > Date()
    }

    private func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default:
            return false
        }
    }

    func toggle(game: Game) async -> Bool {
        if subscribed.contains(game.cfbdId) {
            unsubscribe(gameId: game.cfbdId)
            return true
        }

        guard canSchedule(game) else { return false }
        guard await requestAuthorization() else { return false }

        let fireDate = game.startDate.addingTimeInterval(-3600)

        let content = UNMutableNotificationContent()
        content.title = "\(game.awayTeam) at \(game.homeTeam)"
        content.body = "Kickoff in one hour. Lock in your pick."
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: String(game.cfbdId), content: content, trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            return false
        }

        subscribed.insert(game.cfbdId)
        persist()
        return true
    }

    func unsubscribe(gameId: Int) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [String(gameId)])
        subscribed.remove(gameId)
        persist()
    }
}
