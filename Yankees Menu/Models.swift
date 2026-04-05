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
