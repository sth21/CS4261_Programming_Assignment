import SwiftUI

struct ContentView: View {
    @State private var games: [Game] = []
    @State private var week = 2
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
                ForEach(games) { game in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(game.awayTeam) at \(game.homeTeam)")
                            .font(.headline)
                        Text(game.startDate, format: .dateTime.weekday().month().day().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if game.completed,
                           let home = game.homePoints,
                           let away = game.awayPoints {
                            Text("Final: \(game.homeTeam) \(home), \(game.awayTeam) \(away)")
                                .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("Week \(week)")
            .overlay { if isLoading { ProgressView() } }
            .task { await load() }
        }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            games = try await APIClient.fetchGames(week: week)
        } catch {
            errorMessage = "\(error)"
        }
        isLoading = false
    }
}

#Preview {
    ContentView()
}
