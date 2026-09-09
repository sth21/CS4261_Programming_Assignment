import SwiftUI

struct ContentView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(NotificationStore.self) private var notifications

    @State private var games: [Game] = []
    @State private var picks: [Int: Pick] = [:]
    @State private var record = Record(wins: 0, losses: 0, pending: 0)
    @State private var week = 1
    @State private var conference: String?
    @State private var isLoading = false
    @State private var loadError: APIError?
    @State private var isResolvingWeek = true
    @State private var slateIsFresh = false
    @State private var hasGraded = false
    @State private var submitting: [Int: String] = [:]

    let conferences = ["ACC", "Big Ten", "Big 12", "SEC", "Pac-12", "American Athletic",
                       "Conference USA", "Mid-American", "Mountain West", "Sun Belt",
                       "FBS Independents"]

    var lastSynced: Date? { games.map(\.lastSyncedAt).max() }

    var gamesKey: String { "\(isResolvingWeek)-\(week)-\(conference ?? "all")" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                RecordHeader(record: record)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(1...15, id: \.self) { w in
                            Chip(label: "Week \(w)", isSelected: !isResolvingWeek && week == w) {
                                week = w
                            }
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
            .navigationTitle(isResolvingWeek ? "NCAAFB Pick'em" : "Week \(week)")
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
                    .disabled(isLoading || isResolvingWeek)
                }
            }
            .task { await loadCurrentSlate() }
            .task(id: gamesKey) { await loadGames() }
        }
    }

    @ViewBuilder
    var content: some View {
        if let loadError {
            ErrorState(error: loadError) { Task { await retry() } }
        } else if isResolvingWeek || (isLoading && games.isEmpty) {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        submittingTeam: submitting[game.cfbdId],
                        isSubscribed: notifications.isSubscribed(game.cfbdId),
                        canSubscribe: notifications.canSchedule(game),
                        onTap: { team in Task { await tap(game: game, team: team) } },
                        onBell: { Task { _ = await notifications.toggle(game: game) } }
                    )
                }
            }
            .listStyle(.plain)
            .refreshable { await refresh() }
        }
    }

    func loadCurrentSlate() async {
        guard isResolvingWeek else { return }
        loadError = nil

        do {
            let slate = try await APIClient.fetchCurrentSlate()
            if Task.isCancelled { return }

            games = slate.games
            slateIsFresh = true
            week = slate.week
            isResolvingWeek = false

            await loadPicksAndGrade()
        } catch {
            report(error)
        }
    }

    func loadGames() async {
        guard !isResolvingWeek else { return }
        if slateIsFresh { slateIsFresh = false; return }

        isLoading = true
        loadError = nil
        defer { if !Task.isCancelled { isLoading = false } }

        do {
            var fetched = try await APIClient.fetchGames(week: week, conference: conference)

            if fetched.isEmpty && conference == nil {
                try await APIClient.refreshGames(week: week)
                fetched = try await APIClient.fetchGames(week: week)
            }

            if Task.isCancelled { return }
            games = fetched
            loadError = nil

            await loadPicksAndGrade()
        } catch {
            report(error)
        }
    }

    func loadPicksAndGrade() async {
        guard let token = auth.token else { return }

        do {
            try await loadPicks(token: token)
        } catch {
            report(error)
            return
        }

        if !hasGraded {
            hasGraded = true
            try? await APIClient.gradePicks(token: token)
            try? await loadPicks(token: token)
        }
    }

    func refresh() async {
        isLoading = true
        defer { if !Task.isCancelled { isLoading = false } }

        do {
            try await APIClient.refreshGames(week: week)
            let fetched = try await APIClient.fetchGames(week: week, conference: conference)
            if Task.isCancelled { return }
            games = fetched
            loadError = nil
            if let token = auth.token {
                try await loadPicks(token: token)
            }
        } catch {
            report(error)
        }
    }

    func retry() async {
        if isResolvingWeek {
            await loadCurrentSlate()
        } else {
            await loadGames()
        }
    }

    func tap(game: Game, team: String) async {
        guard !game.isLocked, let token = auth.token else { return }

        submitting[game.cfbdId] = team
        defer { submitting[game.cfbdId] = nil }

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
        } catch {
            if error is CancellationError { return }
            if let apiError = error as? APIError, case .unauthorized = apiError {
                auth.logOut()
                return
            }
            await loadGames()
        }
    }

    func loadPicks(token: String) async throws {
        let response = try await APIClient.fetchPicks(token: token)
        if Task.isCancelled { return }
        picks = Dictionary(uniqueKeysWithValues: response.picks.map { ($0.gameId, $0) })
        record = response.record
    }

    func report(_ error: Error) {
        if error is CancellationError { return }
        if let urlError = error as? URLError, urlError.code == .cancelled { return }

        guard let apiError = error as? APIError else {
            loadError = .offline
            return
        }
        if case .unauthorized = apiError {
            auth.logOut()
            return
        }
        loadError = apiError
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
        case .decoding: "The server sent something we couldn't read."
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
    let submittingTeam: String?
    let isSubscribed: Bool
    let canSubscribe: Bool
    let onTap: (String) -> Void
    let onBell: () -> Void

    var bellEnabled: Bool { isSubscribed || canSubscribe }

    var bellColor: Color {
        if isSubscribed { return .accentColor }
        return canSubscribe ? .secondary : Color(.tertiaryLabel)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                TeamSide(
                    teamId: game.awayId,
                    name: game.awayTeam,
                    isPicked: pick?.predictedWinner == game.awayTeam,
                    isLocked: game.isLocked,
                    isSubmitting: submittingTeam == game.awayTeam,
                    result: pick?.predictedWinner == game.awayTeam ? pick?.isCorrect : nil,
                    onTap: { onTap(game.awayTeam) }
                )

                VStack(spacing: 4) {
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
                        } else {
                            Image(systemName: isSubscribed ? "bell.fill" : "bell")
                                .font(.footnote)
                                .foregroundStyle(bellColor)
                                .frame(width: 32, height: 24)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if bellEnabled { onBell() }
                                }
                        }
                    }
                }
                .frame(width: 90)

                TeamSide(
                    teamId: game.homeId,
                    name: game.homeTeam,
                    isPicked: pick?.predictedWinner == game.homeTeam,
                    isLocked: game.isLocked,
                    isSubmitting: submittingTeam == game.homeTeam,
                    result: pick?.predictedWinner == game.homeTeam ? pick?.isCorrect : nil,
                    onTap: { onTap(game.homeTeam) }
                )
            }

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
    let isSubmitting: Bool
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
        VStack(spacing: 6) {
            AsyncImage(url: logoURL) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Circle().fill(Color(.tertiarySystemFill))
            }
            .frame(width: 44, height: 44)
            .padding(4)
            .overlay(Circle().stroke(ringColor, lineWidth: 3))
            .opacity(isSubmitting ? 0.4 : 1)

            Text(name)
                .font(.caption.weight(isPicked ? .bold : .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isLocked && !isSubmitting { onTap() }
        }
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
        .environment(NotificationStore())
}
