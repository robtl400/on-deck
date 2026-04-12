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
    let officialDate: String      // "2026-04-04"
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
    let name: String
}

// MARK: - Live feed models

private struct LiveFeedResponse: Decodable {
    let gameData: LiveGameData
    let liveData: LiveData
}

private struct LiveGameData: Decodable {
    let status: GameStatus
    let teams: LiveTeams
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
 State machine:

   launch
     │
     ▼
 schedule request ──(Live game found)──► set activeGamePk
     │                                         │
     │(no game / Final / Preview)              ▼
     ▼                                   live feed request ──(Final)──► clear activeGamePk
 resolve state                                 │                               │
     │                                     (Live)                        back to schedule
     ▼                                         ▼                          on next poll
 emit GameState                         emit .live / .final_
 */
final class GameFetcher {

    // Tracks the current game across polls to avoid midnight/date-boundary issues.
    // Cleared when the game reaches Final so doubleheader game 2 is picked up correctly.
    private var activeGamePk: Int? = nil

    // The selected team. Changing this clears activeGamePk so the next poll
    // does a fresh schedule lookup for the new team instead of continuing to
    // track the previous team's live game.
    var teamId: Int = yankeesTeamId {
        didSet { activeGamePk = nil }
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

    // Fetch current game state. Calls completion on an arbitrary background queue.
    func fetchCurrentState(completion: @escaping (GameState) -> Void) {
        // If we're tracking a live game, poll it directly (handles midnight boundaries
        // and eliminates the redundant schedule call during active games).
        if let gamePk = activeGamePk {
            fetchLiveFeed(gamePk: gamePk) { [weak self] state in
                guard let self else { return }
                if case .final_ = state {
                    self.activeGamePk = nil
                    self.fetchNextGame(after: self.todayOfficialDate(), completion: completion)
                } else {
                    completion(state)
                }
            }
            return
        }

        let today = todayOfficialDate()
        let scheduleURL = URL(string: "\(baseURL)/api/v1/schedule?sportId=1&teamId=\(teamId)&date=\(today)")!

        fetch(url: scheduleURL, as: ScheduleResponse.self) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                completion(.error)
            case .success(let response):
                guard let game = self.pickGame(from: response) else {
                    self.fetchNextGame(after: today, completion: completion)
                    return
                }
                self.resolveState(from: game, completion: completion)
            }
        }
    }

    /// Fetches current standings for all 30 teams.
    /// Calls completion on an arbitrary background queue.
    func fetchStandings(season: Int, completion: @escaping (Result<TeamRecords, Error>) -> Void) {
        let url = URL(string: "\(baseURL)/api/v1/standings?leagueId=103,104&season=\(season)")!
        fetch(url: url, as: StandingsResponse.self) { result in
            switch result {
            case .failure(let e):
                completion(.failure(e))
            case .success(let response):
                var records: TeamRecords = [:]
                for divRecord in response.records {
                    for teamRecord in divRecord.teamRecords {
                        records[teamRecord.team.id] = (teamRecord.wins, teamRecord.losses)
                    }
                }
                completion(.success(records))
            }
        }
    }

    // MARK: - Private helpers

    private func resolveState(from game: ScheduleGame, completion: @escaping (GameState) -> Void) {
        let state = game.status.abstractGameState
        let detailed = game.status.detailedState ?? ""

        if detailed == "Postponed" || detailed.contains("Suspended") {
            let (opponentName, opponentId, isHome) = opponentInfo(from: game)
            completion(.postponed(opponent: opponentName, opponentId: opponentId, isHome: isHome))
            return
        }

        switch state {
        case "Preview":
            guard let gameDate = isoFormatter.date(from: game.gameDate) else {
                completion(.error)
                return
            }
            let (opponentName, opponentId, isHome) = opponentInfo(from: game)
            completion(.upcoming(opponent: opponentName, opponentId: opponentId,
                                 isHome: isHome, time: gameDate))

        case "Live":
            activeGamePk = game.gamePk
            fetchLiveFeed(gamePk: game.gamePk) { [weak self] state in
                guard let self else { return }
                if case .final_ = state {
                    self.activeGamePk = nil
                    self.fetchNextGame(after: self.todayOfficialDate(), completion: completion)
                } else {
                    completion(state)
                }
            }

        case "Final":
            activeGamePk = nil
            fetchNextGame(after: todayOfficialDate(), completion: completion)

        default:
            completion(.error)
        }
    }

    private func fetchLiveFeed(gamePk: Int, completion: @escaping (GameState) -> Void) {
        let url = URL(string: "\(baseURL)/api/v1.1/game/\(gamePk)/feed/live")!

        fetch(url: url, as: LiveFeedResponse.self) { result in
            switch result {
            case .failure:
                completion(.error)
            case .success(let feed):
                let status = feed.gameData.status.abstractGameState
                let ls = feed.liveData.linescore
                let awayTeam = feed.gameData.teams.away
                let homeTeam = feed.gameData.teams.home
                let awayRuns = ls.teams.away.runs ?? 0
                let homeRuns = ls.teams.home.runs ?? 0

                switch status {
                case "Live":
                    completion(.live(
                        awayAbbr: awayTeam.abbreviation, awayId: awayTeam.id, awayRuns: awayRuns,
                        homeAbbr: homeTeam.abbreviation, homeId: homeTeam.id, homeRuns: homeRuns,
                        inning: ls.currentInning ?? 1,
                        isTopInning: ls.isTopInning ?? true
                    ))
                case "Final":
                    completion(.final_(
                        awayAbbr: awayTeam.abbreviation, awayId: awayTeam.id, awayRuns: awayRuns,
                        homeAbbr: homeTeam.abbreviation, homeId: homeTeam.id, homeRuns: homeRuns
                    ))
                default:
                    completion(.error)
                }
            }
        }
    }

    // Find the next scheduled game (looks up to 14 days out).
    private func fetchNextGame(after today: String, completion: @escaping (GameState) -> Void) {
        guard let todayDate = Self.officialDateFormatter.date(from: today) else {
            completion(.offSeason)
            return
        }
        let endDate = Self.officialDateFormatter.string(
            from: todayDate.addingTimeInterval(14 * 86400))
        let url = URL(string: "\(baseURL)/api/v1/schedule?sportId=1&teamId=\(teamId)&startDate=\(today)&endDate=\(endDate)")!

        fetch(url: url, as: ScheduleResponse.self) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                completion(.error)
            case .success(let response):
                for date in response.dates {
                    guard date.date != today else { continue }
                    if let game = self.pickGame(from: ScheduleResponse(dates: [date])) {
                        guard let gameDate = self.isoFormatter.date(from: game.gameDate) else { continue }
                        let (opponentName, opponentId, isHome) = self.opponentInfo(from: game)
                        completion(.nextGame(opponent: opponentName, opponentId: opponentId,
                                            isHome: isHome, date: gameDate))
                        return
                    }
                }
                completion(.offSeason)
            }
        }
    }

    // Returns today as "YYYY-MM-DD" in local system time, for consistent
    // today/tomorrow boundary logic with the display layer.
    private func todayOfficialDate() -> String {
        Self.officialDateFormatter.string(from: Date())
    }

    private static let officialDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f
    }()

    // Pick which game to show: prefer Live, then earliest Preview, then Final.
    // Caller passes a single-date ScheduleResponse for 'next game' lookups.
    private func pickGame(from response: ScheduleResponse) -> ScheduleGame? {
        let games = response.dates.flatMap { $0.games }
        if let live = games.first(where: { $0.status.abstractGameState == "Live" }) { return live }
        if let preview = games.filter({ $0.status.abstractGameState == "Preview" })
            .sorted(by: { $0.gameDate < $1.gameDate }).first { return preview }
        if let final_ = games.first(where: { $0.status.abstractGameState == "Final" }) { return final_ }
        return nil
    }

    // Returns (opponentName, opponentId, yankeesAreHome)
    private func opponentInfo(from game: ScheduleGame) -> (name: String, id: Int, isHome: Bool) {
        if game.teams.away.team.id == teamId {
            return (game.teams.home.team.name, game.teams.home.team.id, false)
        } else {
            return (game.teams.away.team.name, game.teams.away.team.id, true)
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

    // MARK: - Generic JSON fetch

    private func fetch<T: Decodable>(url: URL, as type: T.Type,
                                     completion: @escaping (Result<T, Error>) -> Void) {
        let task = session.dataTask(with: url) { data, _, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let data else {
                completion(.failure(URLError(.badServerResponse)))
                return
            }
            do {
                let decoded = try JSONDecoder().decode(T.self, from: data)
                completion(.success(decoded))
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }
}
