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
}
