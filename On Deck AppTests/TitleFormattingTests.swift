import XCTest
@testable import On_Deck_App

/// Covers the menu bar title layout. `makeTitle` renders the same segments the
/// status bar draws, with team abbreviations standing in for logos.
final class TitleFormattingTests: XCTestCase {

    // Fixed future date for predictable time formatting.
    // 2026-04-04 19:05 EDT = 2026-04-04 23:05 UTC
    private let gameTime = Date(timeIntervalSince1970: 1775347500) // approx 7:05 PM ET

    func testUpcomingAway() {
        let title = makeTitle(for: .upcoming(opponentId: 111, isHome: false, time: gameTime))
        XCTAssertTrue(title.hasPrefix("│ NYY @ BOS · "), "got '\(title)'")
        XCTAssertTrue(title.hasSuffix(" │"), "got '\(title)'")
    }

    func testUpcomingHome() {
        let title = makeTitle(for: .upcoming(opponentId: 111, isHome: true, time: gameTime))
        XCTAssertTrue(title.hasPrefix("│ NYY vs BOS · "), "got '\(title)'")
    }

    func testLiveTopInning() {
        let title = makeTitle(for: .live(awayAbbr: "MIA", awayId: 146, awayRuns: 4,
                                         homeAbbr: "NYY", homeId: 147, homeRuns: 0,
                                         inning: 4, isTopInning: true))
        XCTAssertEqual(title, "│ MIA 4 – 0 NYY · 4↑ │")
    }

    func testLiveBottomInning() {
        let title = makeTitle(for: .live(awayAbbr: "MIA", awayId: 146, awayRuns: 4,
                                         homeAbbr: "NYY", homeId: 147, homeRuns: 2,
                                         inning: 7, isTopInning: false))
        XCTAssertEqual(title, "│ MIA 4 – 2 NYY · 7↓ │")
    }

    func testFinalDefaultTeamWin() {
        let title = makeTitle(for: .final_(awayAbbr: "MIA", awayId: 146, awayRuns: 4,
                                           homeAbbr: "NYY", homeId: 147, homeRuns: 5))
        XCTAssertEqual(title, "│ MIA 4 – 5 NYY · W │")
    }

    func testFinalDefaultTeamLose() {
        let title = makeTitle(for: .final_(awayAbbr: "NYY", awayId: 147, awayRuns: 2,
                                           homeAbbr: "BOS", homeId: 111, homeRuns: 6))
        XCTAssertEqual(title, "│ NYY 2 – 6 BOS · L │")
    }

    func testFinalTie() {
        // Suspended/replayed games can end in a tie; display "T" not "W" or "L".
        let title = makeTitle(for: .final_(awayAbbr: "NYY", awayId: 147, awayRuns: 3,
                                           homeAbbr: "BOS", homeId: 111, homeRuns: 3))
        XCTAssertEqual(title, "│ NYY 3 – 3 BOS · T │")
    }

    func testPostponedAway() {
        let title = makeTitle(for: .postponed(opponentId: 111, isHome: false))
        XCTAssertEqual(title, "│ NYY @ BOS · PPD │")
    }

    func testPostponedHome() {
        let title = makeTitle(for: .postponed(opponentId: 111, isHome: true))
        XCTAssertEqual(title, "│ NYY vs BOS · PPD │")
    }

    func testNextGameAway() {
        let title = makeTitle(for: .nextGame(opponentId: 111, isHome: false, date: gameTime))
        XCTAssertTrue(title.hasPrefix("│ NYY @ BOS · "), "got '\(title)'")
    }

    func testNextGameHome() {
        let title = makeTitle(for: .nextGame(opponentId: 111, isHome: true, date: gameTime))
        XCTAssertTrue(title.hasPrefix("│ NYY vs BOS · "), "got '\(title)'")
    }

    func testNextGameOnAnotherDayShowsDate() {
        let title = makeTitle(for: .nextGame(opponentId: 111, isHome: true, date: gameTime))
        if Calendar.current.isDateInToday(gameTime) { return }
        XCTAssertTrue(title.contains("· \(titleDateFormatter.string(from: gameTime)) ·"), "got '\(title)'")
    }

    func testOffSeason() {
        XCTAssertEqual(makeTitle(for: .offSeason), "│ NYY · Off Season │")
    }

    func testErrorKeepsLastKnown() {
        let title = makeTitle(for: .error, lastKnown: "│ MIA 4 – 0 NYY · 4↑ │")
        XCTAssertEqual(title, "│ MIA 4 – 0 NYY · 4↑ │")
    }

    func testErrorProducesNoSegments() {
        XCTAssertNil(titleSegments(for: .error))
    }

    // MARK: - Non-default selected team

    func testFinalOtherTeamWin() {
        let title = makeTitle(
            for: .final_(awayAbbr: "SF", awayId: 137, awayRuns: 2,
                         homeAbbr: "LAD", homeId: 119, homeRuns: 5),
            selectedTeamId: 119)
        XCTAssertEqual(title, "│ SF 2 – 5 LAD · W │")
    }

    func testFinalOtherTeamLose() {
        let title = makeTitle(
            for: .final_(awayAbbr: "LAD", awayId: 119, awayRuns: 1,
                         homeAbbr: "SF", homeId: 137, homeRuns: 4),
            selectedTeamId: 119)
        XCTAssertEqual(title, "│ LAD 1 – 4 SF · L │")
    }

    func testFinalSelectedTeamDidNotPlay() {
        // A final between two other clubs reads as a loss rather than crashing or claiming a win.
        XCTAssertEqual(gameResult(awayId: 137, awayRuns: 2, homeId: 119, homeRuns: 5, selectedTeamId: 147), "L")
    }

    func testOffSeasonOtherTeam() {
        let title = makeTitle(for: .offSeason, selectedTeamId: 119)
        XCTAssertEqual(title, "│ LAD · Off Season │")
    }

    // MARK: - Team table coverage

    func testAllThirtyAbbreviations() {
        let expected: [Int: String] = [
            108: "LAA", 109: "ARI", 110: "BAL", 111: "BOS", 112: "CHC",
            113: "CIN", 114: "CLE", 115: "COL", 116: "DET", 117: "HOU",
            118: "KC",  119: "LAD", 120: "WSH", 121: "NYM", 133: "ATH",
            134: "PIT", 135: "SD",  136: "SEA", 137: "SF",  138: "STL",
            139: "TB",  140: "TEX", 141: "TOR", 142: "MIN", 143: "PHI",
            144: "ATL", 145: "CWS", 146: "MIA", 147: "NYY", 158: "MIL",
        ]
        XCTAssertEqual(mlbTeams.count, 30)
        for (id, abbr) in expected {
            XCTAssertEqual(mlbAbbreviation(for: id), abbr, "Wrong abbreviation for teamId \(id)")
        }
    }

    func testUnknownTeamFallbacks() {
        XCTAssertEqual(mlbAbbreviation(for: 0), "MLB")
        XCTAssertEqual(teamName(for: 0), "Unknown Team")
        XCTAssertEqual(teamNickname(for: 0), "Unknown Team")
    }

    func testTeamTableMatchesDivisions() {
        XCTAssertEqual(Set(mlbTeams.keys), Set(mlbDivisions.flatMap { $0.teamIds }))
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

    // MARK: Standings JSON decode

    func testParseStandingsReadsEveryTeamRecord() {
        let json = """
        {"copyright": "x", "records": [
          {"standingsType": "regularSeason", "league": {"id": 103}, "division": {"id": 201},
           "teamRecords": [
             {"team": {"id": 147, "name": "New York Yankees"}, "wins": 10, "losses": 5, "divisionRank": "1"},
             {"team": {"id": 111, "name": "Boston Red Sox"}, "wins": 6, "losses": 9, "divisionRank": "2"}
           ]},
          {"teamRecords": [
             {"team": {"id": 119}, "wins": 12, "losses": 3}
           ]}
        ]}
        """
        let records = GameFetcher().parseStandings(from: Data(json.utf8))
        XCTAssertEqual(records?.count, 3)
        XCTAssertEqual(records?[147]?.wins, 10)
        XCTAssertEqual(records?[147]?.losses, 5)
        XCTAssertEqual(records?[111]?.wins, 6)
        XCTAssertEqual(records?[119]?.losses, 3)
        XCTAssertNil(records?[999])
    }

    func testParseStandingsEmptySeasonIsEmptyNotNil() {
        // Before Opening Day the API returns no records for the new season.
        let records = GameFetcher().parseStandings(from: Data("{\"records\":[]}".utf8))
        XCTAssertEqual(records?.isEmpty, true)
    }

    func testParseStandingsMalformedIsNil() {
        XCTAssertNil(GameFetcher().parseStandings(from: Data("not json".utf8)))
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

    func testTiedWinPctKeepsAlphabeticalOrder() {
        var standings: TeamRecords = [:]
        for id in alEast.teamIds { standings[id] = (wins: 5, losses: 5) }
        let sorted = teamsSortedByWinPct(in: alEast, standings: standings)
        XCTAssertEqual(sorted, alEast.teamIds)
    }

    func testTeamsWithoutRecordsSortLast() {
        var standings: TeamRecords = [:]
        standings[141] = (wins: 1, losses: 9)   // TOR, worst record but still has one
        let sorted = teamsSortedByWinPct(in: alEast, standings: standings)
        XCTAssertEqual(sorted.first, 141)
        XCTAssertEqual(Array(sorted.dropFirst()), alEast.teamIds.filter { $0 != 141 })
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

    func testDoubleheaderGame2TakesOverOnceGame1IsFinal() {
        let g1 = gameJSON(homeId: 147, homeAbbr: "NYY", homeScore: 5,
                          awayId: 111, awayAbbr: "BOS", awayScore: 3,
                          abstractState: "Final",
                          gameDate: "2026-04-14T13:05:00Z")
        let g2 = gameJSON(homeId: 147, homeAbbr: "NYY", homeScore: nil,
                          awayId: 139, awayAbbr: "TB", awayScore: nil,
                          abstractState: "Preview",
                          gameDate: "2026-04-14T19:10:00Z")
        let result = fetcher.parseTodayGames(from: scheduleJSON(games: [g1, g2]))
        if case .upcoming(let opp, _, _) = result[147] {
            XCTAssertEqual(opp, "TB", "Game 2 should replace the finished game 1")
        } else {
            XCTFail("Expected .upcoming for NYY, got \(String(describing: result[147]))")
        }
        // BOS only played game 1, so it keeps the final.
        if case .final_ = result[111] { } else {
            XCTFail("Expected .final_ for BOS, got \(String(describing: result[111]))")
        }
    }

    func testLiveGameBeatsEarlierUpcomingGame() {
        let live = gameJSON(homeId: 147, homeAbbr: "NYY", homeScore: 2,
                            awayId: 111, awayAbbr: "BOS", awayScore: 1,
                            abstractState: "Live", gameDate: "2026-04-14T19:10:00Z",
                            currentInning: 3, isTopInning: false)
        let preview = gameJSON(homeId: 147, homeAbbr: "NYY", homeScore: nil,
                               awayId: 139, awayAbbr: "TB", awayScore: nil,
                               abstractState: "Preview", gameDate: "2026-04-14T13:05:00Z")
        let result = fetcher.parseTodayGames(from: scheduleJSON(games: [preview, live]))
        if case .live = result[147] { } else {
            XCTFail("Expected .live for NYY, got \(String(describing: result[147]))")
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

final class PickGameTests: XCTestCase {

    private let fetcher = GameFetcher()

    private func game(pk: Int, state: String, date: String) -> String {
        """
        {"gamePk": \(pk), "gameDate": "\(date)",
         "status": {"abstractGameState": "\(state)", "detailedState": "\(state)"},
         "teams": {"home": {"team": {"id": 147}}, "away": {"team": {"id": 111}}}}
        """
    }

    private func schedule(_ games: [String]) -> Data {
        Data("{\"dates\":[{\"date\":\"2026-04-14\",\"games\":[\(games.joined(separator: ","))]}]}".utf8)
    }

    func testLiveBeatsPreviewAndFinal() {
        let data = schedule([game(pk: 1, state: "Final", date: "2026-04-14T13:05:00Z"),
                             game(pk: 2, state: "Live", date: "2026-04-14T17:00:00Z"),
                             game(pk: 3, state: "Preview", date: "2026-04-14T19:10:00Z")])
        XCTAssertEqual(fetcher.pickGamePk(fromScheduleData: data), 2)
    }

    func testEarliestPreviewBeatsFinal() {
        let data = schedule([game(pk: 1, state: "Final", date: "2026-04-14T13:05:00Z"),
                             game(pk: 3, state: "Preview", date: "2026-04-14T23:00:00Z"),
                             game(pk: 2, state: "Preview", date: "2026-04-14T19:10:00Z")])
        XCTAssertEqual(fetcher.pickGamePk(fromScheduleData: data), 2)
    }

    func testMostRecentFinalWhenNothingElse() {
        let data = schedule([game(pk: 1, state: "Final", date: "2026-04-13T23:05:00Z"),
                             game(pk: 2, state: "Final", date: "2026-04-14T17:00:00Z")])
        XCTAssertEqual(fetcher.pickGamePk(fromScheduleData: data), 2)
    }

    func testExpiredFinalIsSkipped() {
        let data = schedule([game(pk: 1, state: "Final", date: "2026-04-14T13:05:00Z"),
                             game(pk: 2, state: "Final", date: "2026-04-14T17:00:00Z")])
        XCTAssertEqual(fetcher.pickGamePk(fromScheduleData: data, excluding: [2]), 1)
        XCTAssertNil(fetcher.pickGamePk(fromScheduleData: data, excluding: [1, 2]))
    }
}

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
