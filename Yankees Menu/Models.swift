import Foundation

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

/// Returns the 6 divisions ordered for the Change Team submenu:
/// the selected team's division first, then same-league divisions by geoTier,
/// then other-league divisions with the matching geoTier first.
func orderedDivisions(for teamId: Int) -> [MLBDivision] {
    guard let myDiv = mlbDivisions.first(where: { $0.teamIds.contains(teamId) }) else {
        return mlbDivisions  // fallback: original order for unknown teamId
    }
    let myLeague    = myDiv.leagueId
    let otherLeague = myLeague == 103 ? 104 : 103

    // Same-league: selected division first, then remaining by geoTier ascending.
    // Guard against self-comparison to preserve strict weak ordering.
    let sameLeague = mlbDivisions
        .filter { $0.leagueId == myLeague }
        .sorted {
            if $0.id == myDiv.id && $1.id != myDiv.id { return true }
            if $1.id == myDiv.id && $0.id != myDiv.id { return false }
            return $0.geoTier < $1.geoTier
        }

    // Other-league: same geoTier as selected division first, then remaining ascending.
    let otherLeagueDivs = mlbDivisions
        .filter { $0.leagueId == otherLeague }
        .sorted {
            if $0.geoTier == myDiv.geoTier && $1.geoTier != myDiv.geoTier { return true }
            if $1.geoTier == myDiv.geoTier && $0.geoTier != myDiv.geoTier { return false }
            return $0.geoTier < $1.geoTier
        }

    return sameLeague + otherLeagueDivs
}
