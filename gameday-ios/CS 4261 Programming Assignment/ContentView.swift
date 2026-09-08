import SwiftUI

struct ContentView: View {
    @Environment(AuthStore.self) private var auth

    @State private var games: [Game] = []
    @State private var picks: [Int: Pick] = [:]
    @State private var record = Record(wins: 0, losses: 0, pending: 0)
    @State private var week = 1
    @State private var conference: String?
    @State private var isLoading = false
    @State private var loadError: APIError?
    @State private var hasResolvedWeek = false
    @State private var submitting: Set<Int> = []

    let conferences = ["ACC", "Big Ten", "Big 12", "SEC", "Pac-12", "American Athletic",
                       "Conference USA", "Mid-American", "Mountain West", "Sun Belt",
                       "FBS Independents"]

    var lastSynced: Date? { games.map(\.lastSyncedAt).max() }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                RecordHeader(record: record)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(1...15, id: \.self) { w in
                            Chip(label: "Week \(w)", isSelected: week == w) { week = w }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 6)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Chip(label: "All", isSelected: conference == nil) { conference = nil }
                        ForEach(conferences, id: \.self) { c in
                            Chip(label: c, isSelected: conference == c) {
                                conference = (conference == c) ? nil : c
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 6)

                if let lastSynced, !games.isEmpty {
                    Text("Synced \(lastSynced, format: .relative(presentation: .named))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                content
            }
            .navigationTitle("Week \(week)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Log Out") { auth.logOut() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
            .task(id: "\(week)-\(conference ?? "all")") { await load() }
        }
    }

    @ViewBuilder
    var content: some View {
        if isLoading && games.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError {
            ErrorState(error: loadError) { Task { await load() } }
        } else if games.isEmpty {
            ContentUnavailableView(
                "No games",
                systemImage: "football",
                description: Text(conference == nil
                    ? "Nothing scheduled for week \(week)."
                    : "No \(conference!) games in week \(week).")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(games) { game in
                    GameRow(
                        game: game,
                        pick: picks[game.cfbdId],
                        isSubmitting: submitting.contains(game.cfbdId),
                        onTap: { team in Task { await tap(game: game, team: team) } }
                    )
                }
            }
            .listStyle(.plain)
            .refreshable { await refresh() }
        }
    }

    func tap(game: Game, team: String) async {
        guard !game.isLocked, let token = auth.token else { return }

        submitting.insert(game.cfbdId)
        defer { submitting.remove(game.cfbdId) }

        do {
            if picks[game.cfbdId]?.predictedWinner == team {
                try await APIClient.deletePick(gameId: game.cfbdId, token: token)
                picks[game.cfbdId] = nil
            } else {
                let pick = try await APIClient.submitPick(
                    gameId: game.cfbdId, winner: team, token: token
                )
                picks[game.cfbdId] = pick
            }
            try await loadPicks(token: token)
        } catch APIError.unauthorized {
            auth.logOut()
        } catch {
            print("tap error: \(error)")
            await load()
        }
    }

    func loadPicks(token: String) async throws {
        let response = try await APIClient.fetchPicks(token: token)
        picks = Dictionary(uniqueKeysWithValues: response.picks.map { ($0.gameId, $0) })
        record = response.record
    }

    func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            if !hasResolvedWeek {
                print("resolving current week…")
                week = (try? await APIClient.fetchCurrentWeek()) ?? 1
                print("resolved to week \(week)")
                hasResolvedWeek = true
                if let token = auth.token {
                    try? await APIClient.gradePicks(token: token)
                }
            }

            print("fetching games week=\(week) conference=\(conference ?? "nil")")
            games = try await APIClient.fetchGames(week: week, conference: conference)
            print("got \(games.count) games")

            if games.isEmpty && conference == nil {
                try await APIClient.refreshGames(week: week)
                games = try await APIClient.fetchGames(week: week)
            }

            if let token = auth.token {
                try await loadPicks(token: token)
                print("picks loaded")
            }
        } catch APIError.unauthorized {
            auth.logOut()
        } catch let error as APIError {
            print("load APIError: \(error)")
            loadError = error
        } catch {
            print("load unknown error: \(error)")
            loadError = .offline
        }
    }

    func refresh() async {
        loadError = nil
        do {
            try await APIClient.refreshGames(week: week)
            games = try await APIClient.fetchGames(week: week, conference: conference)
            if let token = auth.token {
                try await loadPicks(token: token)
            }
        } catch APIError.unauthorized {
            auth.logOut()
        } catch let error as APIError {
            print("refresh APIError: \(error)")
            loadError = error
        } catch {
            print("refresh unknown error: \(error)")
            loadError = .offline
        }
    }
}

struct RecordHeader: View {
    let record: Record

    var body: some View {
        HStack(spacing: 20) {
            stat("\(record.wins)", "W", .green)
            stat("\(record.losses)", "L", .red)
            stat("\(record.pending)", "Pending", .secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
    }

    func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.title3.bold()).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct ErrorState: View {
    let error: APIError
    let retry: () -> Void

    var message: String {
        switch error {
        case .offline: "Can't reach the server. Check your connection."
        case .server: "Something went wrong on our end."
        case .unauthorized: "Your session expired."
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again", action: retry).buttonStyle(.bordered)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct GameRow: View {
    let game: Game
    let pick: Pick?
    let isSubmitting: Bool
    let onTap: (String) -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                TeamSide(
                    teamId: game.awayId,
                    name: game.awayTeam,
                    isPicked: pick?.predictedWinner == game.awayTeam,
                    isLocked: game.isLocked,
                    result: pick?.predictedWinner == game.awayTeam ? pick?.isCorrect : nil,
                    onTap: { onTap(game.awayTeam) }
                )

                VStack(spacing: 2) {
                    if game.completed {
                        HStack(spacing: 10) {
                            Text("\(game.awayPoints ?? 0)")
                                .font(.title2.bold())
                                .foregroundStyle((game.awayPoints ?? 0) > (game.homePoints ?? 0) ? .primary : .secondary)
                            Text("\(game.homePoints ?? 0)")
                                .font(.title2.bold())
                                .foregroundStyle((game.homePoints ?? 0) > (game.awayPoints ?? 0) ? .primary : .secondary)
                        }
                        Text("Final")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(game.startDate, format: .dateTime.weekday().hour().minute())
                            .font(.caption.weight(.medium))
                            .multilineTextAlignment(.center)
                        if game.isLocked {
                            Text("Locked")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: 90)

                TeamSide(
                    teamId: game.homeId,
                    name: game.homeTeam,
                    isPicked: pick?.predictedWinner == game.homeTeam,
                    isLocked: game.isLocked,
                    result: pick?.predictedWinner == game.homeTeam ? pick?.isCorrect : nil,
                    onTap: { onTap(game.homeTeam) }
                )
            }
            .opacity(isSubmitting ? 0.5 : 1)

            if let venue = game.venue {
                Text(venue).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 10)
    }
}

struct TeamSide: View {
    @Environment(\.colorScheme) private var colorScheme
    let teamId: Int?
    let name: String
    let isPicked: Bool
    let isLocked: Bool
    let result: Bool?
    let onTap: () -> Void

    var logoURL: URL? {
        guard let teamId else { return nil }
        let suffix = colorScheme == .dark ? "-dark" : ""
        return URL(string: "https://a.espncdn.com/i/teamlogos/ncaa/500\(suffix)/\(teamId).png")
    }

    var ringColor: Color {
        guard isPicked else { return .clear }
        if let result { return result ? .green : .red }
        return isLocked ? .secondary : .accentColor
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                AsyncImage(url: logoURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Circle().fill(Color(.tertiarySystemFill))
                }
                .frame(width: 44, height: 44)
                .padding(4)
                .overlay(Circle().stroke(ringColor, lineWidth: 3))

                Text(name)
                    .font(.caption.weight(isPicked ? .bold : .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
    }
}

struct Chip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
        .environment(AuthStore())
}
