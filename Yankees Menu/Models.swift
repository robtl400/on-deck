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
