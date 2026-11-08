import Foundation

// MARK: - Decodable models for MLB Stats API

private struct ScheduleResponse: Decodable {
    let dates: [ScheduleDate]
}

private struct ScheduleDate: Decodable {
    let date: String
    let games: [ScheduleGame]
}

private struct ScheduleGame: Decodable {
    let gamePk: Int
    let gameDate: String          // ISO-8601 UTC, e.g. "2026-04-04T23:05:00Z"
    let status: GameStatus
    let teams: ScheduleTeams
}

private struct GameStatus: Decodable {
    let abstractGameState: String // "Preview" | "Live" | "Final"
    let detailedState: String?    // "Postponed", "Suspended", etc.
}

private struct ScheduleTeams: Decodable {
    let away: ScheduleTeamEntry
    let home: ScheduleTeamEntry
}

private struct ScheduleTeamEntry: Decodable {
    let team: TeamRef
    let score: Int?
}

private struct TeamRef: Decodable {
    let id: Int
}

// MARK: - Live feed models

private struct LiveFeedResponse: Decodable {
    let gameData: LiveGameData
    let liveData: LiveData
}

private struct LiveGameData: Decodable {
    let status: GameStatus
    let teams: LiveTeams
    let gameInfo: LiveGameInfo?
}

private struct LiveGameInfo: Decodable {
    let firstPitch: String?
    let gameDurationMinutes: Int?
    let delayDurationMinutes: Int?
}

private struct LiveTeams: Decodable {
    let away: LiveTeamInfo
    let home: LiveTeamInfo
}

private struct LiveTeamInfo: Decodable {
    let id: Int
    let abbreviation: String
}

private struct LiveData: Decodable {
    let linescore: Linescore
}

private struct Linescore: Decodable {
    let currentInning: Int?
    let isTopInning: Bool?
    let teams: LinescoreTeams
}

private struct LinescoreTeams: Decodable {
    let away: LinescoreTeamRuns
    let home: LinescoreTeamRuns
}

private struct LinescoreTeamRuns: Decodable {
    let runs: Int?
}

// MARK: - GameFetcher

/*
 State machine (all callbacks on the main queue):

   poll
     │
     ├─(activeGamePk set)──► live feed ──(Live)──────────► .live
     │                                 ──(Suspended)─────► .postponed, clear activeGamePk
     │                                 ──(Final, recent)─► .final_ for finalDisplayWindow
     │                                 ──(Final, older)──► clear activeGamePk, exclude game, re-poll
     │
     └─(no active game)──► schedule yesterday..today
                              ├── Live     ──► set activeGamePk, live feed (above)
                              ├── Preview  ──► .upcoming
                              ├── Final    ──► live feed (above, for scores + end time)
                              └── nothing  ──► next 14 days ──► .nextGame / .offSeason
 */
final class GameFetcher {

    /// How long a final score stays in the menu bar after the game ends.
    static let finalDisplayWindow: TimeInterval = 30 * 60

    // Tracks the current game across polls so a game that runs past local
    // midnight keeps updating. Cleared when the game ends or is suspended.
    private var activeGamePk: Int? = nil

    // Games whose final-score window has expired this session; the schedule
    // lookup skips them so a doubleheader's second game can take over.
    private var expiredFinals: Set<Int> = []

    // When no end time is available from the API, the first time this session
    // saw the game as Final stands in for it.
    private var finalFirstSeen: [Int: Date] = [:]

    // The selected team. Changing it drops the tracked game and any result
    // still in flight for the previous team.
    var teamId: Int = defaultTeamId {
        didSet {
            activeGamePk = nil
            expiredFinals = []
        }
    }

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    private let baseURL = "https://statsapi.mlb.com"
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private let isoFractionalFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Fetches the current game state for `teamId`. Calls completion on the
    /// main queue. A result for a team that is no longer selected is dropped.
    func fetchCurrentState(completion: @escaping (GameState) -> Void) {
        let requestedTeam = teamId
        let deliver: (GameState) -> Void = { [weak self] state in
            guard let self, self.teamId == requestedTeam else { return }
            completion(state)
        }

        if let gamePk = activeGamePk {
            fetchLiveFeed(gamePk: gamePk, completion: deliver)
        } else {
            lookupSchedule(completion: deliver)
        }
    }

    /// Fetches standings for all 30 teams. Before Opening Day the API returns
    /// no records for the new season, so the previous season is used instead.
    /// Calls completion on the main queue.
    func fetchStandings(season: Int, completion: @escaping (Result<TeamRecords, Error>) -> Void) {
        fetchStandings(season: season, allowFallback: true, completion: completion)
    }

    private func fetchStandings(season: Int, allowFallback: Bool,
                                completion: @escaping (Result<TeamRecords, Error>) -> Void) {
        let url = URL(string: "\(baseURL)/api/v1/standings?leagueId=103,104&season=\(season)")!
        fetchData(url: url) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let e):
                completion(.failure(e))
            case .success(let data):
                guard let records = self.parseStandings(from: data) else {
                    completion(.failure(URLError(.cannotDecodeContentData)))
                    return
                }
                if records.isEmpty, allowFallback {
                    self.fetchStandings(season: season - 1, allowFallback: false, completion: completion)
                } else {
                    completion(.success(records))
                }
            }
        }
    }

    /// Parses a standings payload into `[teamId: (wins, losses)]`.
    /// Internal so unit tests can exercise it with fixture JSON.
    func parseStandings(from data: Data) -> TeamRecords? {
        guard let response = try? JSONDecoder().decode(StandingsResponse.self, from: data) else { return nil }
        var records: TeamRecords = [:]
        for divRecord in response.records {
            for teamRecord in divRecord.teamRecords {
                records[teamRecord.team.id] = (teamRecord.wins, teamRecord.losses)
            }
        }
        return records
    }

    // MARK: - Schedule lookup

    private func lookupSchedule(completion: @escaping (GameState) -> Void) {
        // Yesterday is included so a game still in progress after local
        // midnight is found at launch or after a team switch.
        let today = todayOfficialDate()
        let yesterday = officialDate(daysFromNow: -1)
        let url = URL(string: "\(baseURL)/api/v1/schedule?sportId=1&teamId=\(teamId)&startDate=\(yesterday)&endDate=\(today)")!

        fetch(url: url, as: ScheduleResponse.self) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                completion(.error)
            case .success(let response):
                let games = response.dates.flatMap { $0.games }
                guard let game = Self.pickGame(from: games, excluding: self.expiredFinals) else {
                    self.fetchNextGame(after: today, completion: completion)
                    return
                }
                self.resolveState(from: game, completion: completion)
            }
        }
    }

    private func resolveState(from game: ScheduleGame, completion: @escaping (GameState) -> Void) {
        let detailed = game.status.detailedState ?? ""

        if detailed == "Postponed" || detailed.contains("Suspended") {
            let (opponentId, isHome) = opponentInfo(from: game)
            completion(.postponed(opponentId: opponentId, isHome: isHome))
            return
        }

        switch game.status.abstractGameState {
        case "Preview":
            guard let gameDate = isoFormatter.date(from: game.gameDate) else {
                completion(.error)
                return
            }
            let (opponentId, isHome) = opponentInfo(from: game)
            completion(.upcoming(opponentId: opponentId, isHome: isHome, time: gameDate))

        case "Live":
            activeGamePk = game.gamePk
            fetchLiveFeed(gamePk: game.gamePk, completion: completion)

        case "Final":
            // The live feed supplies the final score and the game's end time.
            fetchLiveFeed(gamePk: game.gamePk, completion: completion)

        default:
            completion(.error)
        }
    }

    // MARK: - Live feed

    private func fetchLiveFeed(gamePk: Int, completion: @escaping (GameState) -> Void) {
        let url = URL(string: "\(baseURL)/api/v1.1/game/\(gamePk)/feed/live")!

        fetch(url: url, as: LiveFeedResponse.self) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                completion(.error)
            case .success(let feed):
                let detailed = feed.gameData.status.detailedState ?? ""
                let ls = feed.liveData.linescore
                let awayTeam = feed.gameData.teams.away
                let homeTeam = feed.gameData.teams.home
                let awayRuns = ls.teams.away.runs ?? 0
                let homeRuns = ls.teams.home.runs ?? 0

                if detailed.contains("Suspended") {
                    // The API keeps a suspended game in the "Live" state until it
                    // resumes, which may be days later.
                    self.activeGamePk = nil
                    let isHome = homeTeam.id == self.teamId
                    completion(.postponed(opponentId: isHome ? awayTeam.id : homeTeam.id, isHome: isHome))
                    return
                }

                switch feed.gameData.status.abstractGameState {
                case "Live":
                    completion(.live(
                        awayAbbr: awayTeam.abbreviation, awayId: awayTeam.id, awayRuns: awayRuns,
                        homeAbbr: homeTeam.abbreviation, homeId: homeTeam.id, homeRuns: homeRuns,
                        inning: ls.currentInning ?? 1,
                        isTopInning: ls.isTopInning ?? true
                    ))

                case "Final":
                    self.activeGamePk = nil
                    if self.isWithinFinalWindow(gamePk: gamePk, info: feed.gameData.gameInfo) {
                        completion(.final_(
                            awayAbbr: awayTeam.abbreviation, awayId: awayTeam.id, awayRuns: awayRuns,
                            homeAbbr: homeTeam.abbreviation, homeId: homeTeam.id, homeRuns: homeRuns
                        ))
                    } else {
                        // Move on: a doubleheader's second game, or the next scheduled game.
                        self.expiredFinals.insert(gamePk)
                        self.lookupSchedule(completion: completion)
                    }

                default:
                    completion(.error)
                }
            }
        }
    }

    /// True while the game's end time is less than `finalDisplayWindow` ago.
    private func isWithinFinalWindow(gamePk: Int, info: LiveGameInfo?) -> Bool {
        let ended: Date
        if let info, let firstPitch = info.firstPitch,
           let start = isoFractionalFormatter.date(from: firstPitch) ?? isoFormatter.date(from: firstPitch),
           let duration = info.gameDurationMinutes {
            ended = start.addingTimeInterval(TimeInterval((duration + (info.delayDurationMinutes ?? 0)) * 60))
        } else if let seen = finalFirstSeen[gamePk] {
            ended = seen
        } else {
            finalFirstSeen[gamePk] = Date()
            ended = Date()
        }
        return Date().timeIntervalSince(ended) < Self.finalDisplayWindow
    }

    // MARK: - Next game

    // Find the next scheduled game after today (looks up to 14 days out).
    // Today's own games are handled by the schedule lookup.
    private func fetchNextGame(after today: String, completion: @escaping (GameState) -> Void) {
        let endDate = officialDate(daysFromNow: 14)
        let url = URL(string: "\(baseURL)/api/v1/schedule?sportId=1&teamId=\(teamId)&startDate=\(today)&endDate=\(endDate)")!

        fetch(url: url, as: ScheduleResponse.self) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                completion(.error)
            case .success(let response):
                for date in response.dates where date.date != today {
                    guard let game = Self.pickGame(from: date.games, excluding: []),
                          let gameDate = self.isoFormatter.date(from: game.gameDate) else { continue }
                    let (opponentId, isHome) = self.opponentInfo(from: game)
                    completion(.nextGame(opponentId: opponentId, isHome: isHome, date: gameDate))
                    return
                }
                completion(.offSeason)
            }
        }
    }

    // MARK: - Dates

    private func todayOfficialDate() -> String { officialDate(daysFromNow: 0) }

    private func officialDate(daysFromNow days: Int) -> String {
        Self.officialDateFormatter.string(from: Date().addingTimeInterval(TimeInterval(days) * 86_400))
    }

    private static let officialDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f
    }()

    // MARK: - Game selection

    // Prefer a live game, then the earliest upcoming game, then the most recent
    // final. `excluding` holds finals whose display window has expired.
    private static func pickGame(from games: [ScheduleGame], excluding: Set<Int>) -> ScheduleGame? {
        let games = games.filter { !excluding.contains($0.gamePk) }
        if let live = games.first(where: { $0.status.abstractGameState == "Live" }) { return live }
        if let preview = games.filter({ $0.status.abstractGameState == "Preview" })
            .min(by: { $0.gameDate < $1.gameDate }) { return preview }
        if let final_ = games.filter({ $0.status.abstractGameState == "Final" })
            .max(by: { $0.gameDate < $1.gameDate }) { return final_ }
        return nil
    }

    /// Test seam for `pickGame`: returns the chosen game's gamePk for a raw
    /// schedule payload.
    func pickGamePk(fromScheduleData data: Data, excluding: Set<Int> = []) -> Int? {
        guard let response = try? JSONDecoder().decode(ScheduleResponse.self, from: data) else { return nil }
        return Self.pickGame(from: response.dates.flatMap { $0.games }, excluding: excluding)?.gamePk
    }

    // Returns (opponentId, selectedTeamIsHome)
    private func opponentInfo(from game: ScheduleGame) -> (id: Int, isHome: Bool) {
        if game.teams.away.team.id == teamId {
            return (game.teams.home.team.id, false)
        } else {
            return (game.teams.away.team.id, true)
        }
    }

    // MARK: - Standings decodables

    private struct StandingsResponse: Decodable { let records: [DivisionRecord] }
    private struct DivisionRecord:    Decodable { let teamRecords: [StandingTeamRecord] }
    private struct StandingTeamRecord: Decodable {
        struct TeamRef: Decodable { let id: Int }
        let team: TeamRef
        let wins: Int
        let losses: Int
    }

    // MARK: - All-games schedule (for standings popover)

    /// Fetches today's game status for all 30 teams and, for teams with no game today,
    /// their next scheduled game within the next 7 days.
    /// Calls completion on the main queue with `[teamId: TodayGameStatus]`.
    /// On network/parse error, calls completion with an empty dict.
    func fetchTodayAllGames(date: Date = Date(),
                            completion: @escaping ([Int: TodayGameStatus]) -> Void) {
        let dateStr     = Self.officialDateFormatter.string(from: date)
        let tomorrowStr = Self.officialDateFormatter.string(from: date.addingTimeInterval(86_400))
        let endDateStr  = Self.officialDateFormatter.string(from: date.addingTimeInterval(7 * 86_400))

        let todayURL  = URL(string: "\(baseURL)/api/v1/schedule?sportId=1&date=\(dateStr)&hydrate=linescore")!
        let futureURL = URL(string: "\(baseURL)/api/v1/schedule?sportId=1&startDate=\(tomorrowStr)&endDate=\(endDateStr)")!

        // Run both requests in parallel; merge results when both finish.
        let group = DispatchGroup()
        var todayGames: [Int: TodayGameStatus] = [:]
        var todayFetchSucceeded = false
        var futureData: Data?

        group.enter()
        session.dataTask(with: todayURL) { [weak self] data, _, error in
            defer { group.leave() }
            guard let self, error == nil, let data else { return }
            todayGames = self.parseTodayGames(from: data)
            todayFetchSucceeded = true
        }.resume()

        group.enter()
        session.dataTask(with: futureURL) { data, _, error in
            defer { group.leave() }
            guard error == nil, let data else { return }
            futureData = data
        }.resume()

        group.notify(queue: .main) { [weak self] in
            guard let self else { completion([:]); return }

            // If today's fetch failed, return empty rather than fabricating
            // .nextGame entries for teams that may actually have games today.
            guard todayFetchSucceeded else { completion([:]); return }

            completion(self.mergeGames(today: todayGames, futureData: futureData))
        }
    }

    /// Merges today's game statuses with future-schedule data.
    /// Internal so unit tests can exercise the merge logic without the network layer.
    func mergeGames(today: [Int: TodayGameStatus], futureData: Data?) -> [Int: TodayGameStatus] {
        var result = today

        // Teams with no game today, plus teams whose game is final — both
        // should show their next scheduled game instead of nothing / a final score.
        let allTeamIds = Set(mlbDivisions.flatMap { $0.teamIds })
        let finalIds   = Set(result.compactMap { (id, status) -> Int? in
            if case .final_ = status { return id } else { return nil }
        })
        let idle = allTeamIds.subtracting(result.keys).union(finalIds)

        if !idle.isEmpty, let data = futureData {
            for (teamId, status) in parseNextGames(from: data, forTeams: idle) {
                result[teamId] = status
            }
        } else if !finalIds.isEmpty {
            // Future fetch unavailable — emit .noGame for stale .final_ entries so
            // the view shows a blank row rather than silently collapsing a stale score.
            for teamId in finalIds {
                result[teamId] = .noGame
            }
        }

        return result
    }

    /// Finds the earliest upcoming game for each team in `teamIds` from a future schedule payload.
    private func parseNextGames(from data: Data, forTeams teamIds: Set<Int>) -> [Int: TodayGameStatus] {
        guard let response = try? JSONDecoder().decode(AllGamesScheduleResponse.self, from: data) else {
            return [:]
        }
        var result: [Int: TodayGameStatus] = [:]
        let games = response.dates.flatMap { $0.games }
            .filter  { $0.status.abstractGameState == "Preview" }
            .sorted  { $0.gameDate < $1.gameDate }

        for game in games {
            guard let gameDate = isoFormatter.date(from: game.gameDate) else { continue }
            let homeId   = game.teams.home.team.id
            let awayId   = game.teams.away.team.id
            let homeAbbr = game.teams.home.team.abbreviation ?? mlbAbbreviation(for: homeId)
            let awayAbbr = game.teams.away.team.abbreviation ?? mlbAbbreviation(for: awayId)

            if teamIds.contains(homeId) && result[homeId] == nil {
                result[homeId] = .nextGame(opponentAbbr: awayAbbr, isHome: true, date: gameDate)
            }
            if teamIds.contains(awayId) && result[awayId] == nil {
                result[awayId] = .nextGame(opponentAbbr: homeAbbr, isHome: false, date: gameDate)
            }

            // Early exit once every idle team has a next game.
            if result.count == teamIds.count { break }
        }
        return result
    }

    /// Parses a hydrated schedule Data payload into a per-team status dict.
    /// When a team plays twice (doubleheader, resumed suspended game), the
    /// live game wins, then the earliest upcoming game, then the final.
    /// Exposed as `internal` so unit tests can call it with fixture JSON.
    func parseTodayGames(from data: Data) -> [Int: TodayGameStatus] {
        guard let response = try? JSONDecoder().decode(AllGamesScheduleResponse.self, from: data) else {
            return [:]
        }
        var result: [Int: (status: TodayGameStatus, rank: Int, gameDate: String)] = [:]
        let allGames = response.dates.flatMap { $0.games }

        func offer(_ status: TodayGameStatus, rank: Int, gameDate: String, to teamId: Int) {
            if let current = result[teamId] {
                let better = rank < current.rank || (rank == current.rank && gameDate < current.gameDate)
                guard better else { return }
            }
            result[teamId] = (status, rank, gameDate)
        }

        for game in allGames {
            let homeId   = game.teams.home.team.id
            let awayId   = game.teams.away.team.id
            let homeAbbr = game.teams.home.team.abbreviation ?? mlbAbbreviation(for: homeId)
            let awayAbbr = game.teams.away.team.abbreviation ?? mlbAbbreviation(for: awayId)
            let detailed = game.status.detailedState ?? ""
            let state    = game.status.abstractGameState

            let homeStatus: TodayGameStatus
            let awayStatus: TodayGameStatus
            let rank: Int

            if detailed == "Postponed" || detailed.contains("Suspended") {
                homeStatus = .postponed
                awayStatus = .postponed
                rank = 3
            } else if state == "Preview" {
                guard let gameDate = isoFormatter.date(from: game.gameDate) else { continue }
                homeStatus = .upcoming(opponentAbbr: awayAbbr, isHome: true, time: gameDate)
                awayStatus = .upcoming(opponentAbbr: homeAbbr, isHome: false, time: gameDate)
                rank = 1
            } else if state == "Live" {
                let homeRuns = game.teams.home.score ?? 0
                let awayRuns = game.teams.away.score ?? 0
                let inning   = game.linescore?.currentInning ?? 1
                let isTop    = game.linescore?.isTopInning ?? true
                homeStatus = .live(opponentAbbr: awayAbbr, isHome: true,
                                   myRuns: homeRuns, theirRuns: awayRuns,
                                   inning: inning, isTopInning: isTop)
                awayStatus = .live(opponentAbbr: homeAbbr, isHome: false,
                                   myRuns: awayRuns, theirRuns: homeRuns,
                                   inning: inning, isTopInning: isTop)
                rank = 0
            } else if state == "Final" {
                let homeRuns = game.teams.home.score ?? 0
                let awayRuns = game.teams.away.score ?? 0
                homeStatus = .final_(opponentAbbr: awayAbbr, isHome: true,
                                     myRuns: homeRuns, theirRuns: awayRuns)
                awayStatus = .final_(opponentAbbr: homeAbbr, isHome: false,
                                     myRuns: awayRuns, theirRuns: homeRuns)
                rank = 2
            } else {
                continue
            }

            offer(homeStatus, rank: rank, gameDate: game.gameDate, to: homeId)
            offer(awayStatus, rank: rank, gameDate: game.gameDate, to: awayId)
        }
        return result.mapValues { $0.status }
    }

    // MARK: - All-games decodable structs (private to file; parseTodayGames exposed for testing)

    private struct AllGamesScheduleResponse: Decodable { let dates: [AllGamesDate] }
    private struct AllGamesDate: Decodable { let games: [AllGamesGame] }
    private struct AllGamesGame: Decodable {
        let gameDate: String
        let status: GameStatus
        let teams: AllGamesTeams
        let linescore: AllGamesLinescore?
    }
    private struct AllGamesTeams: Decodable {
        let away: AllGamesTeamEntry
        let home: AllGamesTeamEntry
    }
    private struct AllGamesTeamEntry: Decodable {
        // `abbreviation` is NOT returned by the base schedule endpoint — only when
        // the response is hydrated. Make it optional and fall back to the local
        // lookup so parseTodayGames never fails silently due to a missing key.
        struct TeamRef: Decodable { let id: Int; let abbreviation: String? }
        let team: TeamRef
        let score: Int?
    }
    private struct AllGamesLinescore: Decodable {
        let currentInning: Int?
        let isTopInning: Bool?
    }

    // MARK: - Generic fetch (completion on the main queue)

    private func fetch<T: Decodable>(url: URL, as type: T.Type,
                                     completion: @escaping (Result<T, Error>) -> Void) {
        fetchData(url: url) { result in
            completion(result.flatMap { data in
                Result { try JSONDecoder().decode(T.self, from: data) }
            })
        }
    }

    private func fetchData(url: URL, completion: @escaping (Result<Data, Error>) -> Void) {
        session.dataTask(with: url) { data, _, error in
            let result: Result<Data, Error>
            if let error {
                result = .failure(error)
            } else if let data {
                result = .success(data)
            } else {
                result = .failure(URLError(.badServerResponse))
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }
}
