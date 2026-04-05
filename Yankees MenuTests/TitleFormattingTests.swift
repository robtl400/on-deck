import XCTest
@testable import Yankees_Menu

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

    func testFinalYankeesWin() {
        let title = makeTitle(for: .final_(awayAbbr: "MIA", awayId: 146, awayRuns: 4,
                                           homeAbbr: "NYY", homeId: 147, homeRuns: 5))
        XCTAssertEqual(title, "MIA 4 – 5 NYY · W")
    }

    func testFinalYankeesLose() {
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

    // MARK: - Non-Yankees selected team

    func testFinalNonYankeesWin() {
        // Dodgers (119) are home and win — selectedTeamId must drive the W/L label.
        let title = makeTitle(
            for: .final_(awayAbbr: "SF", awayId: 137, awayRuns: 2,
                         homeAbbr: "LAD", homeId: 119, homeRuns: 5),
            selectedTeamId: 119)
        XCTAssertEqual(title, "SF 2 – 5 LAD · W")
    }

    func testFinalNonYankeesLose() {
        // Dodgers (119) are away and lose.
        let title = makeTitle(
            for: .final_(awayAbbr: "LAD", awayId: 119, awayRuns: 1,
                         homeAbbr: "SF", homeId: 137, homeRuns: 4),
            selectedTeamId: 119)
        XCTAssertEqual(title, "LAD 1 – 4 SF · L")
    }

    func testOffSeasonNonYankees() {
        // Off-season label should reflect the selected team, not always "NYY".
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
