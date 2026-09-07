import SwiftUI

struct ContentView: View {
    @Environment(AuthStore.self) private var auth

    @State private var games: [Game] = []
    @State private var week = 1
    @State private var conference: String?
    @State private var isLoading = false
    @State private var loadError: APIError?
    @State private var hasResolvedWeek = false

    let conferences = ["ACC", "Big Ten", "Big 12", "SEC", "Pac-12", "American Athletic",
                       "Conference USA", "Mid-American", "Mountain West", "Sun Belt",
                       "FBS Independents"]

    var lastSynced: Date? {
        games.map(\.lastSyncedAt).max()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    GameRow(game: game)
                }
            }
            .listStyle(.plain)
            .refreshable { await refresh() }
        }
    }

    func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            if !hasResolvedWeek {
                week = (try? await APIClient.fetchCurrentWeek()) ?? 1
                hasResolvedWeek = true
            }

            games = try await APIClient.fetchGames(week: week, conference: conference)

            if games.isEmpty && conference == nil {
                try await APIClient.refreshGames(week: week)
                games = try await APIClient.fetchGames(week: week)
            }
        } catch APIError.unauthorized {
            auth.logOut()
        } catch let error as APIError {
            loadError = error
        } catch {
            loadError = .offline
        }
    }

    func refresh() async {
        loadError = nil
        do {
            try await APIClient.refreshGames(week: week)
            games = try await APIClient.fetchGames(week: week, conference: conference)
        } catch APIError.unauthorized {
            auth.logOut()
        } catch let error as APIError {
            loadError = error
        } catch {
            loadError = .offline
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
            Button("Try Again", action: retry)
                .buttonStyle(.bordered)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct GameRow: View {
    let game: Game

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                TeamSide(teamId: game.awayId, name: game.awayTeam)

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
                    }
                }
                .frame(width: 90)

                TeamSide(teamId: game.homeId, name: game.homeTeam)
            }

            if let venue = game.venue {
                Text(venue)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 10)
    }
}

struct TeamSide: View {
    @Environment(\.colorScheme) private var colorScheme
    let teamId: Int?
    let name: String

    var logoURL: URL? {
        guard let teamId else { return nil }
        let suffix = colorScheme == .dark ? "-dark" : ""
        return URL(string: "https://a.espncdn.com/i/teamlogos/ncaa/500\(suffix)/\(teamId).png")
    }

    var body: some View {
        VStack(spacing: 6) {
            AsyncImage(url: logoURL) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Circle().fill(Color(.tertiarySystemFill))
            }
            .frame(width: 44, height: 44)

            Text(name)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
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
