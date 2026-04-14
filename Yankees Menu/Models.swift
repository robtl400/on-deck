import Cocoa

let yankeesTeamId = 147

enum GameState {
    case upcoming(opponent: String, opponentId: Int, isHome: Bool, time: Date)
    case live(awayAbbr: String, awayId: Int, awayRuns: Int,
              homeAbbr: String, homeId: Int, homeRuns: Int,
              inning: Int, isTopInning: Bool)
    case final_(awayAbbr: String, awayId: Int, awayRuns: Int,
                homeAbbr: String, homeId: Int, homeRuns: Int)
    case postponed(opponent: String, opponentId: Int, isHome: Bool)
    case nextGame(opponent: String, opponentId: Int, isHome: Bool, date: Date)
    case offSeason
    case error
}

// MARK: - Team abbreviations (all 30 MLB teams)

func teamAbbreviation(_ name: String) -> String {
    let table: [String: String] = [
        "Arizona Diamondbacks": "ARI",
        "Atlanta Braves":       "ATL",
        "Baltimore Orioles":    "BAL",
        "Boston Red Sox":       "BOS",
        "Chicago Cubs":         "CHC",
        "Chicago White Sox":    "CWS",
        "Cincinnati Reds":      "CIN",
        "Cleveland Guardians":  "CLE",
        "Colorado Rockies":     "COL",
        "Detroit Tigers":       "DET",
        "Houston Astros":       "HOU",
        "Kansas City Royals":   "KC",
        "Los Angeles Angels":   "LAA",
        "Los Angeles Dodgers":  "LAD",
        "Miami Marlins":        "MIA",
        "Milwaukee Brewers":    "MIL",
        "Minnesota Twins":      "MIN",
        "New York Mets":        "NYM",
        "New York Yankees":     "NYY",
        "Oakland Athletics":    "OAK",
        "Athletics":            "ATH",
        "Philadelphia Phillies":"PHI",
        "Pittsburgh Pirates":   "PIT",
        "San Diego Padres":     "SD",
        "San Francisco Giants": "SF",
        "Seattle Mariners":     "SEA",
        "St. Louis Cardinals":  "STL",
        "Tampa Bay Rays":       "TB",
        "Texas Rangers":        "TEX",
        "Toronto Blue Jays":    "TOR",
        "Washington Nationals": "WSH",
    ]
    if let abbr = table[name] { return abbr }
    // Fallback: first letter of each word, max 3 chars
    return name.split(separator: " ").prefix(3).map { String($0.prefix(1)) }.joined()
}

// MARK: - ESPN logo codes (all 30 MLB teams)
// Used to load Assets.xcassets imagesets named "logo-{code}".

func espnCode(for teamId: Int) -> String {
    let table: [Int: String] = [
        108: "laa",   // Los Angeles Angels
        109: "ari",   // Arizona Diamondbacks
        110: "bal",   // Baltimore Orioles
        111: "bos",   // Boston Red Sox
        112: "chc",   // Chicago Cubs
        113: "cin",   // Cincinnati Reds
        114: "cle",   // Cleveland Guardians
        115: "col",   // Colorado Rockies
        116: "det",   // Detroit Tigers
        117: "hou",   // Houston Astros
        118: "kc",    // Kansas City Royals
        119: "lad",   // Los Angeles Dodgers
        120: "wsh",   // Washington Nationals
        121: "nym",   // New York Mets
        133: "oak",   // Athletics (ESPN CDN still uses "oak")
        134: "pit",   // Pittsburgh Pirates
        135: "sd",    // San Diego Padres
        136: "sea",   // Seattle Mariners
        137: "sf",    // San Francisco Giants
        138: "stl",   // St. Louis Cardinals
        139: "tb",    // Tampa Bay Rays
        140: "tex",   // Texas Rangers
        141: "tor",   // Toronto Blue Jays
        142: "min",   // Minnesota Twins
        143: "phi",   // Philadelphia Phillies
        144: "atl",   // Atlanta Braves
        145: "cws",   // Chicago White Sox
        146: "mia",   // Miami Marlins
        147: "nyy",   // New York Yankees
        158: "mil",   // Milwaukee Brewers
    ]
    return table[teamId] ?? "mlb"  // fallback: generic MLB logo
}

// MARK: - Division standings

struct MLBDivision {
    let id: Int         // MLB Stats API division ID
    let name: String    // "AL East", "NL West", etc.
    let leagueId: Int   // 103 = AL, 104 = NL
    let geoTier: Int    // 0 = East, 1 = Central, 2 = West
    let teamIds: [Int]  // in alphabetical name order
}

let mlbDivisions: [MLBDivision] = [
    MLBDivision(id: 201, name: "AL East",
                leagueId: 103, geoTier: 0,
                teamIds: [110, 111, 147, 139, 141]),  // BAL, BOS, NYY, TB, TOR
    MLBDivision(id: 202, name: "AL Central",
                leagueId: 103, geoTier: 1,
                teamIds: [145, 114, 116, 118, 142]),  // CWS, CLE, DET, KC, MIN
    MLBDivision(id: 200, name: "AL West",
                leagueId: 103, geoTier: 2,
                teamIds: [108, 133, 117, 136, 140]),  // LAA, ATH, HOU, SEA, TEX
    MLBDivision(id: 204, name: "NL East",
                leagueId: 104, geoTier: 0,
                teamIds: [144, 146, 121, 143, 120]),  // ATL, MIA, NYM, PHI, WSH
    MLBDivision(id: 205, name: "NL Central",
                leagueId: 104, geoTier: 1,
                teamIds: [112, 113, 158, 134, 138]),  // CHC, CIN, MIL, PIT, STL
    MLBDivision(id: 203, name: "NL West",
                leagueId: 104, geoTier: 2,
                teamIds: [109, 115, 119, 135, 137]),  // ARI, COL, LAD, SD, SF
]

/// teamId → full display name (e.g. "New York Yankees").
/// Returns "Unknown Team" for unrecognised IDs — callers don't crash.
func teamName(for teamId: Int) -> String {
    let table: [Int: String] = [
        108: "Los Angeles Angels",
        109: "Arizona Diamondbacks",
        110: "Baltimore Orioles",
        111: "Boston Red Sox",
        112: "Chicago Cubs",
        113: "Cincinnati Reds",
        114: "Cleveland Guardians",
        115: "Colorado Rockies",
        116: "Detroit Tigers",
        117: "Houston Astros",
        118: "Kansas City Royals",
        119: "Los Angeles Dodgers",
        120: "Washington Nationals",
        121: "New York Mets",
        133: "Athletics",
        134: "Pittsburgh Pirates",
        135: "San Diego Padres",
        136: "Seattle Mariners",
        137: "San Francisco Giants",
        138: "St. Louis Cardinals",
        139: "Tampa Bay Rays",
        140: "Texas Rangers",
        141: "Toronto Blue Jays",
        142: "Minnesota Twins",
        143: "Philadelphia Phillies",
        144: "Atlanta Braves",
        145: "Chicago White Sox",
        146: "Miami Marlins",
        147: "New York Yankees",
        158: "Milwaukee Brewers",
    ]
    return table[teamId] ?? "Unknown Team"
}

/// teamId → (wins, losses). Populated by fetchStandings.
typealias TeamRecords = [Int: (wins: Int, losses: Int)]

// MARK: - Today's game status (per team, for the standings popover)

enum TodayGameStatus {
    case upcoming(opponentAbbr: String, isHome: Bool, time: Date)
    case live(opponentAbbr: String, isHome: Bool, myRuns: Int, theirRuns: Int,
              inning: Int, isTopInning: Bool)
    case final_(opponentAbbr: String, isHome: Bool, myRuns: Int, theirRuns: Int)
    case postponed
    case noGame
}

// MARK: - Game info string (used by TeamRowView and unit tests)

private let popoverTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "h:mm a"
    f.timeZone = .current
    return f
}()

/// Returns the display string for a team's game info cell (e.g. "● 4–2 ↑5", "vs BOS 7:05 PM").
func gameInfoString(for status: TodayGameStatus) -> String {
    switch status {
    case .upcoming(let opp, let isHome, let time):
        let prefix = isHome ? "vs" : "@"
        return "\(prefix) \(opp) \(popoverTimeFormatter.string(from: time))"
    case .live(_, _, let myRuns, let theirRuns, let inning, let isTop):
        let arrow = isTop ? "↑" : "↓"
        return "● \(myRuns)–\(theirRuns) \(arrow)\(inning)"
    case .final_(_, _, let myRuns, let theirRuns):
        if myRuns > theirRuns { return "W \(myRuns)–\(theirRuns)" }
        else if myRuns < theirRuns { return "L \(myRuns)–\(theirRuns)" }
        else { return "T \(myRuns)–\(theirRuns)" }
    case .postponed:
        return "PPD"
    case .noGame:
        return "—"
    }
}

// MARK: - Logo image (shared between AppDelegate status bar and standings popover)

/// Loads a team logo from Assets.xcassets at the given size.
/// Returns nil if the asset is missing.
func logoImage(for teamId: Int, size: NSSize = NSSize(width: 18, height: 18)) -> NSImage? {
    let code = espnCode(for: teamId)
    guard let img = NSImage(named: "logo-\(code)") else { return nil }
    let copy = img.copy() as! NSImage
    copy.isTemplate = false
    copy.size = size
    return copy
}

/// teamId → team nickname only (e.g. "Orioles", "Yankees").
/// Used in the standings popover where the logo already supplies city context.
func teamNickname(for teamId: Int) -> String {
    let table: [Int: String] = [
        108: "Angels",
        109: "Diamondbacks",
        110: "Orioles",
        111: "Red Sox",
        112: "Cubs",
        113: "Reds",
        114: "Guardians",
        115: "Rockies",
        116: "Tigers",
        117: "Astros",
        118: "Royals",
        119: "Dodgers",
        120: "Nationals",
        121: "Mets",
        133: "Athletics",
        134: "Pirates",
        135: "Padres",
        136: "Mariners",
        137: "Giants",
        138: "Cardinals",
        139: "Rays",
        140: "Rangers",
        141: "Blue Jays",
        142: "Twins",
        143: "Phillies",
        144: "Braves",
        145: "White Sox",
        146: "Marlins",
        147: "Yankees",
        158: "Brewers",
    ]
    return table[teamId] ?? teamName(for: teamId)
}

// MARK: - Standings sort helpers

/// Returns teamIds in the given division sorted by win percentage descending.
/// Falls back to stable original order when standings are nil or a team is missing.
func teamsSortedByWinPct(in division: MLBDivision, standings: TeamRecords?) -> [Int] {
    division.teamIds.sorted { a, b in
        guard let ra = standings?[a], let rb = standings?[b] else { return false }
        let wpA = Double(ra.wins) / Double(max(1, ra.wins + ra.losses))
        let wpB = Double(rb.wins) / Double(max(1, rb.wins + rb.losses))
        return wpA > wpB
    }
}
