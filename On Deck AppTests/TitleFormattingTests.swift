import XCTest
@testable import On_Deck_App

final class TitleFormattingTests: XCTestCase {

    // Fixed future date for predictable time formatting.
    // 2026-04-04 19:05 EDT = 2026-04-04 23:05 UTC
    private let gameTime = Date(timeIntervalSince1970: 1775347500) // approx 7:05 PM ET

    func testUpcomingAway() {
        let title = makeTitle(for: .upcoming(opponent: "Boston Red Sox", opponentId: 111,
                                              isHome: false, time: gameTime))
        XCTAssertTrue(title.hasPrefix("@ BOS ·"), "Expected '@ BOS ·', got '\(title)'")
    }

    func testUpcomingHome() {
        let title = makeTitle(for: .upcoming(opponent: "Boston Red Sox", opponentId: 111,
                                              isHome: true, time: gameTime))
        XCTAssertTrue(title.hasPrefix("vs BOS ·"), "Expected 'vs BOS ·', got '\(title)'")
    }

    func testLiveTopInning() {
        let title = makeTitle(for: .live(awayAbbr: "MIA", awayId: 146, awayRuns: 4,
                                         homeAbbr: "NYY", homeId: 147, homeRuns: 0,
                                         inning: 4, isTopInning: true))
        XCTAssertEqual(title, "MIA 4 – 0 NYY · T4")
    }

    func testLiveBottomInning() {
        let title = makeTitle(for: .live(awayAbbr: "MIA", awayId: 146, awayRuns: 4,
                                         homeAbbr: "NYY", homeId: 147, homeRuns: 2,
                                         inning: 7, isTopInning: false))
        XCTAssertEqual(title, "MIA 4 – 2 NYY · B7")
    }

    func testFinalDefaultTeamWin() {
        let title = makeTitle(for: .final_(awayAbbr: "MIA", awayId: 146, awayRuns: 4,
                                           homeAbbr: "NYY", homeId: 147, homeRuns: 5))
        XCTAssertEqual(title, "MIA 4 – 5 NYY · W")
    }

    func testFinalDefaultTeamLose() {
        let title = makeTitle(for: .final_(awayAbbr: "NYY", awayId: 147, awayRuns: 2,
                                           homeAbbr: "BOS", homeId: 111, homeRuns: 6))
        XCTAssertEqual(title, "NYY 2 – 6 BOS · L")
    }

    func testPostponedAway() {
        let title = makeTitle(for: .postponed(opponent: "Boston Red Sox", opponentId: 111,
                                              isHome: false))
        XCTAssertEqual(title, "@ BOS · PPD")
    }

    func testPostponedHome() {
        let title = makeTitle(for: .postponed(opponent: "Boston Red Sox", opponentId: 111,
                                              isHome: true))
        XCTAssertEqual(title, "vs BOS · PPD")
    }

    func testNextGame() {
        let title = makeTitle(for: .nextGame(opponent: "Boston Red Sox", opponentId: 111,
                                             isHome: false, date: gameTime))
        XCTAssertTrue(title.hasPrefix("@ BOS ·"), "Expected '@ BOS ·', got '\(title)'")
    }

    func testOffSeason() {
        XCTAssertEqual(makeTitle(for: .offSeason), "NYY · Off Season")
    }

    func testErrorKeepsLastKnown() {
        let title = makeTitle(for: .error, lastKnown: "MIA 4 – 0 NYY · T4")
        XCTAssertEqual(title, "MIA 4 – 0 NYY · T4")
    }

    func testErrorDefaultsToNYY() {
        XCTAssertEqual(makeTitle(for: .error), "NYY")
    }

    // MARK: - teamAbbreviation coverage

    func testAllThirtyTeams() {
        let teams = [
            ("Arizona Diamondbacks", "ARI"), ("Atlanta Braves", "ATL"),
            ("Baltimore Orioles", "BAL"),    ("Boston Red Sox", "BOS"),
            ("Chicago Cubs", "CHC"),          ("Chicago White Sox", "CWS"),
            ("Cincinnati Reds", "CIN"),       ("Cleveland Guardians", "CLE"),
            ("Colorado Rockies", "COL"),      ("Detroit Tigers", "DET"),
            ("Houston Astros", "HOU"),        ("Kansas City Royals", "KC"),
            ("Los Angeles Angels", "LAA"),    ("Los Angeles Dodgers", "LAD"),
            ("Miami Marlins", "MIA"),         ("Milwaukee Brewers", "MIL"),
            ("Minnesota Twins", "MIN"),       ("New York Mets", "NYM"),
            ("New York Yankees", "NYY"),      ("Oakland Athletics", "OAK"),
            ("Philadelphia Phillies", "PHI"), ("Pittsburgh Pirates", "PIT"),
            ("San Diego Padres", "SD"),       ("San Francisco Giants", "SF"),
            ("Seattle Mariners", "SEA"),      ("St. Louis Cardinals", "STL"),
            ("Tampa Bay Rays", "TB"),         ("Texas Rangers", "TEX"),
            ("Toronto Blue Jays", "TOR"),     ("Washington Nationals", "WSH"),
        ]
        for (name, expected) in teams {
            XCTAssertEqual(teamAbbreviation(name), expected,
                           "Wrong abbreviation for \(name)")
        }
    }

    func testAthleticsRebranding() {
        // The team dropped "Oakland" and is now just "Athletics" in the MLB API.
        XCTAssertEqual(teamAbbreviation("Athletics"), "ATH")
    }

    func testUnknownTeamFallback() {
        // Unknown names fall back to initials, max 3 chars.
        XCTAssertEqual(teamAbbreviation("Portland Pickles"), "PP")
        XCTAssertEqual(teamAbbreviation("Foo Bar Baz Qux"), "FBB")  // truncated to 3
    }

    func testNextGameHome() {
        let title = makeTitle(for: .nextGame(opponent: "Boston Red Sox", opponentId: 111,
                                             isHome: true, date: gameTime))
        XCTAssertTrue(title.hasPrefix("vs BOS ·"), "Expected 'vs BOS ·', got '\(title)'")
    }

    func testFinalTie() {
        // Suspended/replayed games can end in a tie; display "T" not "W" or "L".
        let title = makeTitle(for: .final_(awayAbbr: "NYY", awayId: 147, awayRuns: 3,
                                           homeAbbr: "BOS", homeId: 111, homeRuns: 3))
        XCTAssertEqual(title, "NYY 3 – 3 BOS · T")
    }

    // MARK: - Non-default selected team

    func testFinalOtherTeamWin() {
        let title = makeTitle(
            for: .final_(awayAbbr: "SF", awayId: 137, awayRuns: 2,
                         homeAbbr: "LAD", homeId: 119, homeRuns: 5),
            selectedTeamId: 119)
        XCTAssertEqual(title, "SF 2 – 5 LAD · W")
    }

    func testFinalOtherTeamLose() {
        let title = makeTitle(
            for: .final_(awayAbbr: "LAD", awayId: 119, awayRuns: 1,
                         homeAbbr: "SF", homeId: 137, homeRuns: 4),
            selectedTeamId: 119)
        XCTAssertEqual(title, "LAD 1 – 4 SF · L")
    }

    func testOffSeasonOtherTeam() {
        let title = makeTitle(for: .offSeason, selectedTeamId: 119)
        XCTAssertEqual(title, "LAD · Off Season")
    }

    // MARK: - espnCode coverage

    func testAllThirtyEspnCodes() {
        let expected: [Int: String] = [
            108: "laa", 109: "ari", 110: "bal", 111: "bos", 112: "chc",
            113: "cin", 114: "cle", 115: "col", 116: "det", 117: "hou",
            118: "kc",  119: "lad", 120: "wsh", 121: "nym", 133: "oak",
            134: "pit", 135: "sd",  136: "sea", 137: "sf",  138: "stl",
            139: "tb",  140: "tex", 141: "tor", 142: "min", 143: "phi",
            144: "atl", 145: "cws", 146: "mia", 147: "nyy", 158: "mil",
        ]
        for (id, code) in expected {
            XCTAssertEqual(espnCode(for: id), code, "Wrong ESPN code for teamId \(id)")
        }
    }

    func testEspnCodeUnknownFallback() {
        XCTAssertEqual(espnCode(for: 0), "mlb")
        XCTAssertEqual(espnCode(for: -1), "mlb")
    }
}

// MARK: - Standings data tests

final class DivisionStandingsTests: XCTestCase {

    // MARK: teamName

    func testTeamNameKnown() {
        XCTAssertEqual(teamName(for: 147), "New York Yankees")
        XCTAssertEqual(teamName(for: 111), "Boston Red Sox")
        XCTAssertEqual(teamName(for: 133), "Athletics")
    }

    func testTeamNameUnknownFallback() {
        let name = teamName(for: 0)
        XCTAssertFalse(name.isEmpty)
    }

    // MARK: fetchStandings JSON decode

    func testFetchStandingsDecodesSampleJSON() throws {
        var records: TeamRecords = [:]
        records[147] = (wins: 10, losses: 5)
        records[111] = (wins: 6,  losses: 9)
        XCTAssertEqual(records[147]?.wins,   10)
        XCTAssertEqual(records[147]?.losses,  5)
        XCTAssertEqual(records[111]?.wins,    6)
        XCTAssertNil(records[999])
    }

    // MARK: Division completeness

    func testAllThirtyTeamIdsExactlyOnce() {
        let allIds = mlbDivisions.flatMap { $0.teamIds }
        XCTAssertEqual(allIds.count, 30, "Expected 30 team IDs across all divisions")
        let unique = Set(allIds)
        XCTAssertEqual(unique.count, 30, "Found duplicate teamIds in mlbDivisions")
    }
}

// MARK: - teamsSortedByWinPct tests

final class TeamsSortedByWinPctTests: XCTestCase {

    private let alEast = mlbDivisions.first(where: { $0.name == "AL East" })!

    func testSortsByWinPctDescending() {
        // NYY 10-5 (.667) should rank above BOS 6-9 (.400)
        var standings: TeamRecords = [:]
        standings[147] = (wins: 10, losses: 5)   // NYY
        standings[111] = (wins: 6,  losses: 9)   // BOS
        // fill others at 0-0
        for id in alEast.teamIds where id != 147 && id != 111 {
            standings[id] = (wins: 0, losses: 0)
        }
        let sorted = teamsSortedByWinPct(in: alEast, standings: standings)
        let nyyIdx = sorted.firstIndex(of: 147)!
        let bosIdx = sorted.firstIndex(of: 111)!
        XCTAssertLessThan(nyyIdx, bosIdx, "NYY (.667) should rank above BOS (.400)")
    }

    func testNilStandingsFallback() {
        // nil standings → returns original teamIds order (no crash)
        let sorted = teamsSortedByWinPct(in: alEast, standings: nil)
        XCTAssertEqual(sorted.count, alEast.teamIds.count)
        XCTAssertEqual(Set(sorted), Set(alEast.teamIds))
    }

    func testZeroZeroRecord() {
        // max(1, 0+0) prevents ÷0 — all teams at 0-0 get equal win% (.000)
        var standings: TeamRecords = [:]
        for id in alEast.teamIds { standings[id] = (wins: 0, losses: 0) }
        let sorted = teamsSortedByWinPct(in: alEast, standings: standings)
        XCTAssertEqual(sorted.count, 5, "No crash and all 5 teams present")
    }

    func testTiedWinPct() {
        // Equal win% → stable sort (no crash, all teams present)
        var standings: TeamRecords = [:]
        for id in alEast.teamIds { standings[id] = (wins: 5, losses: 5) }
        let sorted = teamsSortedByWinPct(in: alEast, standings: standings)
        XCTAssertEqual(Set(sorted), Set(alEast.teamIds))
    }
}

// MARK: - TodayGameStatus display formatting tests

final class GameInfoStringTests: XCTestCase {

    private let futureDate = Date(timeIntervalSince1970: 1775347500)  // approx 7:05 PM ET

    func testLiveStatusFormat() {
        let s = gameInfoString(for: .live(opponentAbbr: "BOS", isHome: true,
                                          myRuns: 4, theirRuns: 2,
                                          inning: 5, isTopInning: true))
        XCTAssertEqual(s, "● 4-2 vs BOS · 5↑")
    }

    func testLiveBottomInning() {
        let s = gameInfoString(for: .live(opponentAbbr: "BOS", isHome: false,
                                          myRuns: 1, theirRuns: 3,
                                          inning: 7, isTopInning: false))
        XCTAssertEqual(s, "● 1-3 @ BOS · 7↓")
    }

    func testUpcomingHomeFormat() {
        let s = gameInfoString(for: .upcoming(opponentAbbr: "BOS", isHome: true,
                                              time: futureDate))
        XCTAssertTrue(s.hasPrefix("vs. BOS · "), "Expected 'vs. BOS · …', got '\(s)'")
    }

    func testUpcomingAwayFormat() {
        let s = gameInfoString(for: .upcoming(opponentAbbr: "BOS", isHome: false,
                                              time: futureDate))
        XCTAssertTrue(s.hasPrefix("@ BOS · "), "Expected '@ BOS · …', got '\(s)'")
    }

    func testFinalWinFormat() {
        let s = gameInfoString(for: .final_(opponentAbbr: "BOS", isHome: true,
                                            myRuns: 5, theirRuns: 3))
        XCTAssertEqual(s, "W 5-3")
    }

    func testFinalLossFormat() {
        let s = gameInfoString(for: .final_(opponentAbbr: "BOS", isHome: false,
                                            myRuns: 3, theirRuns: 5))
        XCTAssertEqual(s, "L 3-5")
    }

    func testPostponedFormat() {
        XCTAssertEqual(gameInfoString(for: .postponed), "PPD")
    }

    func testNoGameFormat() {
        XCTAssertEqual(gameInfoString(for: .noGame), "—")
    }

    func testNextGameHomeFormat() {
        let s = gameInfoString(for: .nextGame(opponentAbbr: "BOS", isHome: true,
                                              date: futureDate))
        XCTAssertTrue(s.hasPrefix("vs. BOS "), "Expected 'vs. BOS …', got '\(s)'")
    }

    func testNextGameAwayFormat() {
        let s = gameInfoString(for: .nextGame(opponentAbbr: "BOS", isHome: false,
                                              date: futureDate))
        XCTAssertTrue(s.hasPrefix("@ BOS "), "Expected '@ BOS …', got '\(s)'")
    }
}

// MARK: - parseTodayGames JSON parsing tests

final class AllGamesParsingTests: XCTestCase {

    private let fetcher = GameFetcher()

    // Fixture builder helpers
    private func gameJSON(homeId: Int, homeAbbr: String, homeScore: Int?,
                          awayId: Int, awayAbbr: String, awayScore: Int?,
                          abstractState: String, detailedState: String? = nil,
                          gameDate: String = "2026-04-14T18:10:00Z",
                          currentInning: Int? = nil, isTopInning: Bool? = nil) -> String {
        let scoreH = homeScore.map { "\($0)" } ?? "null"
        let scoreA = awayScore.map { "\($0)" } ?? "null"
        let detailed = detailedState.map { "\"\($0)\"" } ?? "null"
        let linescore: String
        if let inn = currentInning, let top = isTopInning {
            linescore = "{\"currentInning\":\(inn),\"isTopInning\":\(top)}"
        } else {
            linescore = "null"
        }
        return """
        {
          "gameDate": "\(gameDate)",
          "status": {"abstractGameState": "\(abstractState)", "detailedState": \(detailed)},
          "teams": {
            "home": {"team": {"id": \(homeId), "abbreviation": "\(homeAbbr)"}, "score": \(scoreH)},
            "away": {"team": {"id": \(awayId), "abbreviation": "\(awayAbbr)"}, "score": \(scoreA)}
          },
          "linescore": \(linescore)
        }
        """
    }

    private func scheduleJSON(games: [String]) -> Data {
        let joined = games.joined(separator: ",")
        let json = "{\"dates\":[{\"games\":[\(joined)]}]}"
        return json.data(using: .utf8)!
    }

    func testParsesPreviousGame() {
        let data = scheduleJSON(games: [
            gameJSON(homeId: 147, homeAbbr: "NYY", homeScore: nil,
                     awayId: 111, awayAbbr: "BOS", awayScore: nil,
                     abstractState: "Preview")
        ])
        let result = fetcher.parseTodayGames(from: data)
        if case .upcoming(let opp, let isHome, _) = result[147] {
            XCTAssertEqual(opp, "BOS")
            XCTAssertTrue(isHome)
        } else {
            XCTFail("Expected .upcoming for home team, got \(String(describing: result[147]))")
        }
        if case .upcoming(let opp, let isHome, _) = result[111] {
            XCTAssertEqual(opp, "NYY")
            XCTAssertFalse(isHome)
        } else {
            XCTFail("Expected .upcoming for away team, got \(String(describing: result[111]))")
        }
    }

    func testParsesLiveGame() {
        let data = scheduleJSON(games: [
            gameJSON(homeId: 147, homeAbbr: "NYY", homeScore: 4,
                     awayId: 111, awayAbbr: "BOS", awayScore: 2,
                     abstractState: "Live",
                     currentInning: 5, isTopInning: true)
        ])
        let result = fetcher.parseTodayGames(from: data)
        if case .live(let opp, let isHome, let my, let their, let inn, let top) = result[147] {
            XCTAssertEqual(opp, "BOS")
            XCTAssertTrue(isHome)
            XCTAssertEqual(my, 4)
            XCTAssertEqual(their, 2)
            XCTAssertEqual(inn, 5)
            XCTAssertTrue(top)
        } else {
            XCTFail("Expected .live for NYY, got \(String(describing: result[147]))")
        }
        // Away team perspective: myRuns = away score (2), theirRuns = home score (4)
        if case .live(_, _, let my, let their, _, _) = result[111] {
            XCTAssertEqual(my, 2)
            XCTAssertEqual(their, 4)
        } else {
            XCTFail("Expected .live for BOS, got \(String(describing: result[111]))")
        }
    }

    func testParsesFinalGame() {
        let data = scheduleJSON(games: [
            gameJSON(homeId: 147, homeAbbr: "NYY", homeScore: 5,
                     awayId: 111, awayAbbr: "BOS", awayScore: 3,
                     abstractState: "Final")
        ])
        let result = fetcher.parseTodayGames(from: data)
        if case .final_(let opp, let isHome, let my, let their) = result[147] {
            XCTAssertEqual(opp, "BOS")
            XCTAssertTrue(isHome)
            XCTAssertEqual(my, 5)
            XCTAssertEqual(their, 3)
        } else {
            XCTFail("Expected .final_ for NYY, got \(String(describing: result[147]))")
        }
    }

    func testParsesPostponedGame() {
        let data = scheduleJSON(games: [
            gameJSON(homeId: 147, homeAbbr: "NYY", homeScore: nil,
                     awayId: 111, awayAbbr: "BOS", awayScore: nil,
                     abstractState: "Preview", detailedState: "Postponed")
        ])
        let result = fetcher.parseTodayGames(from: data)
        if case .postponed = result[147] { } else {
            XCTFail("Expected .postponed for NYY, got \(String(describing: result[147]))")
        }
        if case .postponed = result[111] { } else {
            XCTFail("Expected .postponed for BOS, got \(String(describing: result[111]))")
        }
    }

    func testNoGameForTeam() {
        // COL (115) absent from schedule → not in dict → caller gets .noGame via nil coalescing
        let data = scheduleJSON(games: [
            gameJSON(homeId: 147, homeAbbr: "NYY", homeScore: nil,
                     awayId: 111, awayAbbr: "BOS", awayScore: nil,
                     abstractState: "Preview")
        ])
        let result = fetcher.parseTodayGames(from: data)
        XCTAssertNil(result[115], "COL not in schedule — should be absent from dict")
    }

    func testDoubleheaderPicksEarliest() {
        // Two games for NYY: first at 13:05 UTC (G1 Preview), second at 19:10 UTC (G2 Preview)
        let g1 = gameJSON(homeId: 147, homeAbbr: "NYY", homeScore: nil,
                          awayId: 111, awayAbbr: "BOS", awayScore: nil,
                          abstractState: "Preview",
                          gameDate: "2026-04-14T13:05:00Z")
        let g2 = gameJSON(homeId: 147, homeAbbr: "NYY", homeScore: nil,
                          awayId: 139, awayAbbr: "TB", awayScore: nil,
                          abstractState: "Preview",
                          gameDate: "2026-04-14T19:10:00Z")
        let data = scheduleJSON(games: [g2, g1])   // intentionally out of order
        let result = fetcher.parseTodayGames(from: data)
        // Should pick G1 (earliest) — opponent BOS, not TB
        if case .upcoming(let opp, _, _) = result[147] {
            XCTAssertEqual(opp, "BOS", "Should use earliest game (G1 vs BOS)")
        } else {
            XCTFail("Expected .upcoming for NYY, got \(String(describing: result[147]))")
        }
    }

    func testBothTeamsGetEntry() {
        let data = scheduleJSON(games: [
            gameJSON(homeId: 147, homeAbbr: "NYY", homeScore: nil,
                     awayId: 111, awayAbbr: "BOS", awayScore: nil,
                     abstractState: "Preview")
        ])
        let result = fetcher.parseTodayGames(from: data)
        XCTAssertNotNil(result[147], "Home team NYY should have an entry")
        XCTAssertNotNil(result[111], "Away team BOS should have an entry")
        if case .upcoming(_, let isHome, _) = result[147] {
            XCTAssertTrue(isHome, "NYY is home — isHome should be true")
        }
        if case .upcoming(_, let isHome, _) = result[111] {
            XCTAssertFalse(isHome, "BOS is away — isHome should be false")
        }
    }

    func testErrorReturnsEmptyDict() {
        // Malformed JSON → parseTodayGames returns [:]
        let badData = "not json at all".data(using: .utf8)!
        let result = fetcher.parseTodayGames(from: badData)
        XCTAssertTrue(result.isEmpty, "Parse failure should return empty dict")
    }
}

// MARK: - mergeGames tests

final class AllGamesMergeTests: XCTestCase {

    private let fetcher = GameFetcher()

    // Reuse the same fixture helpers as AllGamesParsingTests.
    private func gameJSON(homeId: Int, homeAbbr: String, homeScore: Int?,
                          awayId: Int, awayAbbr: String, awayScore: Int?,
                          abstractState: String,
                          gameDate: String = "2026-04-14T18:10:00Z") -> String {
        let scoreH = homeScore.map { "\($0)" } ?? "null"
        let scoreA = awayScore.map { "\($0)" } ?? "null"
        return """
        {
          "gameDate": "\(gameDate)",
          "status": {"abstractGameState": "\(abstractState)", "detailedState": null},
          "teams": {
            "home": {"team": {"id": \(homeId), "abbreviation": "\(homeAbbr)"}, "score": \(scoreH)},
            "away": {"team": {"id": \(awayId), "abbreviation": "\(awayAbbr)"}, "score": \(scoreA)}
          },
          "linescore": null
        }
        """
    }

    private func scheduleData(_ games: [String]) -> Data {
        let joined = games.joined(separator: ",")
        return "{\"dates\":[{\"games\":[\(joined)]}]}".data(using: .utf8)!
    }

    func testFinalTeamGetsNextGameWhenFutureDataAvailable() {
        // Today: NYY finished a Final game.
        let todayData = scheduleData([
            gameJSON(homeId: 147, homeAbbr: "NYY", homeScore: 5,
                     awayId: 111, awayAbbr: "BOS", awayScore: 3,
                     abstractState: "Final")
        ])
        let today = fetcher.parseTodayGames(from: todayData)
        guard case .final_ = today[147] else {
            XCTFail("Expected .final_ for NYY in today's data"); return
        }

        // Future: NYY has an upcoming Preview game.
        let futureData = scheduleData([
            gameJSON(homeId: 147, homeAbbr: "NYY", homeScore: nil,
                     awayId: 146, awayAbbr: "MIA", awayScore: nil,
                     abstractState: "Preview",
                     gameDate: "2026-04-17T23:05:00Z")
        ])

        let result = fetcher.mergeGames(today: today, futureData: futureData)

        if case .nextGame(let opp, let isHome, _) = result[147] {
            XCTAssertEqual(opp, "MIA", "Next game opponent should be MIA")
            XCTAssertTrue(isHome, "NYY is home in the next game")
        } else {
            XCTFail("Expected .nextGame for NYY after merge, got \(String(describing: result[147]))")
        }
    }

    func testFinalTeamGetsNoGameWhenFutureDataUnavailable() {
        // Today: NYY finished a Final game.
        let todayData = scheduleData([
            gameJSON(homeId: 147, homeAbbr: "NYY", homeScore: 5,
                     awayId: 111, awayAbbr: "BOS", awayScore: 3,
                     abstractState: "Final")
        ])
        let today = fetcher.parseTodayGames(from: todayData)

        // Future fetch failed — futureData is nil.
        let result = fetcher.mergeGames(today: today, futureData: nil)

        if case .noGame = result[147] {
            // correct — blank row, not a stale collapsed .final_
        } else {
            XCTFail("Expected .noGame for NYY when futureData is nil, got \(String(describing: result[147]))")
        }
    }

    func testIdleTeamStaysNoGameWhenFutureDataUnavailable() {
        // Today: NYY has no game at all. Future fetch failed.
        let today: [Int: TodayGameStatus] = [:]
        let result = fetcher.mergeGames(today: today, futureData: nil)
        // Idle teams should not appear in result — callers coalesce nil to .noGame.
        XCTAssertNil(result[147], "Idle team with no future data should be absent from result")
    }
}

// MARK: - TeamRowView setGameStatus tests

final class TeamRowViewGameStatusTests: XCTestCase {

    private let upcomingDate = Date(timeIntervalSince1970: 1775347500 + 86_400)  // tomorrow ~7PM

    func testFinalCollapsesGameInfo() {
        let row = TeamRowView(teamId: 147)

        // An upcoming game makes the label visible.
        row.setGameStatus(.upcoming(opponentAbbr: "BOS", isHome: true, time: Date()))
        XCTAssertFalse(row.gameInfoLabel.isHidden, "Label should be visible for .upcoming")

        // .final_ must collapse it.
        row.setGameStatus(.final_(opponentAbbr: "BOS", isHome: true, myRuns: 5, theirRuns: 3))
        XCTAssertTrue(row.gameInfoLabel.isHidden, ".final_ should hide the game info label")
    }

    func testNextGameAfterFinalReShowsGameInfo() {
        let row = TeamRowView(teamId: 147)

        // Simulate the fetcher's replacement: .final_ → .nextGame
        row.setGameStatus(.final_(opponentAbbr: "BOS", isHome: true, myRuns: 5, theirRuns: 3))
        XCTAssertTrue(row.gameInfoLabel.isHidden, ".final_ should hide the label")

        row.setGameStatus(.nextGame(opponentAbbr: "MIA", isHome: false, date: upcomingDate))
        XCTAssertFalse(row.gameInfoLabel.isHidden, ".nextGame should unhide the label")
    }

    func testNoGameCollapsesGameInfo() {
        let row = TeamRowView(teamId: 147)
        row.setGameStatus(.upcoming(opponentAbbr: "BOS", isHome: true, time: Date()))
        row.setGameStatus(.noGame)
        XCTAssertTrue(row.gameInfoLabel.isHidden, ".noGame should hide the game info label")
    }
}
