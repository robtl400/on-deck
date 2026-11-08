import Cocoa

let defaultTeamId = 147

enum GameState {
    case upcoming(opponentId: Int, isHome: Bool, time: Date)
    case live(awayAbbr: String, awayId: Int, awayRuns: Int,
              homeAbbr: String, homeId: Int, homeRuns: Int,
              inning: Int, isTopInning: Bool)
    case final_(awayAbbr: String, awayId: Int, awayRuns: Int,
                homeAbbr: String, homeId: Int, homeRuns: Int)
    case postponed(opponentId: Int, isHome: Bool)
    case nextGame(opponentId: Int, isHome: Bool, date: Date)
    case offSeason
    case error
}

// MARK: - Teams (all 30 MLB clubs, keyed by MLB Stats API team id)

struct MLBTeam {
    let id: Int
    let abbreviation: String   // official MLB abbreviation, e.g. "NYY"
    let name: String           // full name, e.g. "New York Yankees"
    let nickname: String       // e.g. "Yankees"
}

let mlbTeams: [Int: MLBTeam] = Dictionary(uniqueKeysWithValues: [
    MLBTeam(id: 108, abbreviation: "LAA", name: "Los Angeles Angels", nickname: "Angels"),
    MLBTeam(id: 109, abbreviation: "ARI", name: "Arizona Diamondbacks", nickname: "Diamondbacks"),
    MLBTeam(id: 110, abbreviation: "BAL", name: "Baltimore Orioles", nickname: "Orioles"),
    MLBTeam(id: 111, abbreviation: "BOS", name: "Boston Red Sox", nickname: "Red Sox"),
    MLBTeam(id: 112, abbreviation: "CHC", name: "Chicago Cubs", nickname: "Cubs"),
    MLBTeam(id: 113, abbreviation: "CIN", name: "Cincinnati Reds", nickname: "Reds"),
    MLBTeam(id: 114, abbreviation: "CLE", name: "Cleveland Guardians", nickname: "Guardians"),
    MLBTeam(id: 115, abbreviation: "COL", name: "Colorado Rockies", nickname: "Rockies"),
    MLBTeam(id: 116, abbreviation: "DET", name: "Detroit Tigers", nickname: "Tigers"),
    MLBTeam(id: 117, abbreviation: "HOU", name: "Houston Astros", nickname: "Astros"),
    MLBTeam(id: 118, abbreviation: "KC", name: "Kansas City Royals", nickname: "Royals"),
    MLBTeam(id: 119, abbreviation: "LAD", name: "Los Angeles Dodgers", nickname: "Dodgers"),
    MLBTeam(id: 120, abbreviation: "WSH", name: "Washington Nationals", nickname: "Nationals"),
    MLBTeam(id: 121, abbreviation: "NYM", name: "New York Mets", nickname: "Mets"),
    MLBTeam(id: 133, abbreviation: "ATH", name: "Athletics", nickname: "Athletics"),
    MLBTeam(id: 134, abbreviation: "PIT", name: "Pittsburgh Pirates", nickname: "Pirates"),
    MLBTeam(id: 135, abbreviation: "SD", name: "San Diego Padres", nickname: "Padres"),
    MLBTeam(id: 136, abbreviation: "SEA", name: "Seattle Mariners", nickname: "Mariners"),
    MLBTeam(id: 137, abbreviation: "SF", name: "San Francisco Giants", nickname: "Giants"),
    MLBTeam(id: 138, abbreviation: "STL", name: "St. Louis Cardinals", nickname: "Cardinals"),
    MLBTeam(id: 139, abbreviation: "TB", name: "Tampa Bay Rays", nickname: "Rays"),
    MLBTeam(id: 140, abbreviation: "TEX", name: "Texas Rangers", nickname: "Rangers"),
    MLBTeam(id: 141, abbreviation: "TOR", name: "Toronto Blue Jays", nickname: "Blue Jays"),
    MLBTeam(id: 142, abbreviation: "MIN", name: "Minnesota Twins", nickname: "Twins"),
    MLBTeam(id: 143, abbreviation: "PHI", name: "Philadelphia Phillies", nickname: "Phillies"),
    MLBTeam(id: 144, abbreviation: "ATL", name: "Atlanta Braves", nickname: "Braves"),
    MLBTeam(id: 145, abbreviation: "CWS", name: "Chicago White Sox", nickname: "White Sox"),
    MLBTeam(id: 146, abbreviation: "MIA", name: "Miami Marlins", nickname: "Marlins"),
    MLBTeam(id: 147, abbreviation: "NYY", name: "New York Yankees", nickname: "Yankees"),
    MLBTeam(id: 158, abbreviation: "MIL", name: "Milwaukee Brewers", nickname: "Brewers"),
].map { ($0.id, $0) })

/// Official abbreviation; also the text fallback wherever a logo has not loaded.
/// Returns "MLB" for unrecognised ids.
func mlbAbbreviation(for teamId: Int) -> String {
    mlbTeams[teamId]?.abbreviation ?? "MLB"
}

/// Full display name. Returns "Unknown Team" for unrecognised ids so callers never crash.
func teamName(for teamId: Int) -> String {
    mlbTeams[teamId]?.name ?? "Unknown Team"
}

/// Nickname only, for the standings popover where the logo supplies city context.
func teamNickname(for teamId: Int) -> String {
    mlbTeams[teamId]?.nickname ?? teamName(for: teamId)
}

// MARK: - Division standings

struct MLBDivision {
    let id: Int         // MLB Stats API division ID
    let name: String    // "AL East", "NL West", etc.
    let teamIds: [Int]  // in alphabetical name order
}

let mlbDivisions: [MLBDivision] = [
    MLBDivision(id: 201, name: "AL East",
                teamIds: [110, 111, 147, 139, 141]),  // BAL, BOS, NYY, TB, TOR
    MLBDivision(id: 202, name: "AL Central",
                teamIds: [145, 114, 116, 118, 142]),  // CWS, CLE, DET, KC, MIN
    MLBDivision(id: 200, name: "AL West",
                teamIds: [108, 133, 117, 136, 140]),  // LAA, ATH, HOU, SEA, TEX
    MLBDivision(id: 204, name: "NL East",
                teamIds: [144, 146, 121, 143, 120]),  // ATL, MIA, NYM, PHI, WSH
    MLBDivision(id: 205, name: "NL Central",
                teamIds: [112, 113, 158, 134, 138]),  // CHC, CIN, MIL, PIT, STL
    MLBDivision(id: 203, name: "NL West",
                teamIds: [109, 115, 119, 135, 137]),  // ARI, COL, LAD, SD, SF
]

/// teamId → (wins, losses). Populated by fetchStandings.
typealias TeamRecords = [Int: (wins: Int, losses: Int)]

// MARK: - Today's game status (per team, for the standings popover)

enum TodayGameStatus {
    case upcoming(opponentAbbr: String, isHome: Bool, time: Date)
    case live(opponentAbbr: String, isHome: Bool, myRuns: Int, theirRuns: Int,
              inning: Int, isTopInning: Bool)
    case final_(opponentAbbr: String, isHome: Bool, myRuns: Int, theirRuns: Int)
    case postponed
    /// Team has no game today; shows their next scheduled game.
    case nextGame(opponentAbbr: String, isHome: Bool, date: Date)
    case noGame
}

// MARK: - Game info string (used by TeamRowView and unit tests)

private let popoverTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "h:mm a"
    f.timeZone = .current
    return f
}()

/// "4/15" — for next-game date display.
private let popoverNextDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "M/d"
    f.timeZone = .current
    return f
}()

/// "7pm" — hour-only, lowercase, for next-game time display.
private let popoverShortTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "ha"
    f.amSymbol = "am"
    f.pmSymbol = "pm"
    f.timeZone = .current
    return f
}()

/// Returns the display string for a team's game info cell.
func gameInfoString(for status: TodayGameStatus) -> String {
    switch status {
    case .upcoming(let opp, let isHome, let time):
        let prefix = isHome ? "vs." : "@"
        return "\(prefix) \(opp) · \(popoverTimeFormatter.string(from: time))"
    case .live(let opp, let isHome, let myRuns, let theirRuns, let inning, let isTop):
        let vsAt  = isHome ? "vs" : "@"
        let arrow = isTop ? "↑" : "↓"
        return "● \(myRuns)-\(theirRuns) \(vsAt) \(opp) · \(inning)\(arrow)"
    case .final_(_, _, let myRuns, let theirRuns):
        if myRuns > theirRuns { return "W \(myRuns)-\(theirRuns)" }
        else if myRuns < theirRuns { return "L \(myRuns)-\(theirRuns)" }
        else { return "T \(myRuns)-\(theirRuns)" }
    case .postponed:
        return "PPD"
    case .nextGame(let opp, let isHome, let date):
        let prefix = isHome ? "vs." : "@"
        let dateStr = popoverNextDateFormatter.string(from: date)
        let timeStr = popoverShortTimeFormatter.string(from: date)
        return "\(prefix) \(opp) \(dateStr) \(timeStr)"
    case .noGame:
        return "—"
    }
}

// MARK: - Logo image (shared between AppDelegate status bar and standings popover)

/// Returns the team logo at the given size, or nil while `TeamLogoStore`
/// is still downloading it. Observe `TeamLogoStore.didLoadLogo` to redraw.
func logoImage(for teamId: Int, size: NSSize = NSSize(width: 18, height: 18)) -> NSImage? {
    guard let img = TeamLogoStore.shared.image(for: teamId) else { return nil }
    // MLB's logos are not square: aspect-fit onto a square canvas so callers
    // can lay them out at a fixed size without stretching.
    let source = img.size
    guard source.width > 0, source.height > 0 else { return nil }
    let scale = min(size.width / source.width, size.height / source.height)
    let fitted = NSSize(width: source.width * scale, height: source.height * scale)
    let origin = NSPoint(x: (size.width - fitted.width) / 2, y: (size.height - fitted.height) / 2)
    let canvas = NSImage(size: size, flipped: false) { _ in
        img.draw(in: NSRect(origin: origin, size: fitted))
        return true
    }
    canvas.isTemplate = false
    return canvas
}

// MARK: - Standings sort helpers

/// Returns teamIds in the given division sorted by win percentage descending.
/// Ties, and teams without a record, keep their original (alphabetical) order;
/// teams without a record sort after teams that have one.
func teamsSortedByWinPct(in division: MLBDivision, standings: TeamRecords?) -> [Int] {
    func winPct(_ id: Int) -> Double? {
        guard let r = standings?[id] else { return nil }
        return Double(r.wins) / Double(max(1, r.wins + r.losses))
    }
    return division.teamIds.enumerated().sorted { a, b in
        switch (winPct(a.element), winPct(b.element)) {
        case let (pa?, pb?) where pa != pb: return pa > pb
        case (.some, .none):                 return true
        case (.none, .some):                 return false
        default:                             return a.offset < b.offset
        }
    }.map { $0.element }
}
