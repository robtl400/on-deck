import Foundation

/// One piece of the menu bar title. The status bar renders `.team` as a logo
/// (or its abbreviation while the logo downloads); plain-text rendering uses
/// the abbreviation. Keeping the layout here means both renderings, and the
/// unit tests, share one source of truth.
enum TitleSegment: Equatable {
    case separator
    case dot
    case text(String)
    case team(Int)
}

/// Lays out the menu bar title for a game state. Returns nil for `.error`,
/// where the caller keeps whatever it was showing.
func titleSegments(for state: GameState, selectedTeamId: Int = defaultTeamId) -> [TitleSegment]? {
    switch state {
    case .upcoming(let opponentId, let isHome, let time):
        return matchup(selectedTeamId, opponentId, isHome) + [.dot, .text("\(titleTimeFormatter.string(from: time)) "), .separator]

    case .live(_, let awayId, let awayRuns, _, let homeId, let homeRuns, let inning, let isTop):
        return score(awayId, awayRuns, homeId, homeRuns) + [.dot, .text("\(inning)\(isTop ? "↑" : "↓") "), .separator]

    case .final_(_, let awayId, let awayRuns, _, let homeId, let homeRuns):
        let result = gameResult(awayId: awayId, awayRuns: awayRuns,
                                homeId: homeId, homeRuns: homeRuns,
                                selectedTeamId: selectedTeamId)
        return score(awayId, awayRuns, homeId, homeRuns) + [.dot, .text("\(result) "), .separator]

    case .postponed(let opponentId, let isHome):
        return matchup(selectedTeamId, opponentId, isHome) + [.dot, .text("PPD "), .separator]

    case .nextGame(let opponentId, let isHome, let date):
        var segments = matchup(selectedTeamId, opponentId, isHome)
        if !Calendar.current.isDateInToday(date) {
            segments += [.dot, .text(titleDateFormatter.string(from: date))]
        }
        segments += [.dot, .text("\(titleTimeFormatter.string(from: date)) "), .separator]
        return segments

    case .offSeason:
        return [.separator, .text(" "), .team(selectedTeamId), .dot, .text("Off Season "), .separator]

    case .error:
        return nil
    }
}

/// "W", "L" or "T" from the selected team's point of view.
func gameResult(awayId: Int, awayRuns: Int, homeId: Int, homeRuns: Int, selectedTeamId: Int) -> String {
    if awayRuns == homeRuns { return "T" }
    if awayId == selectedTeamId { return awayRuns > homeRuns ? "W" : "L" }
    if homeId == selectedTeamId { return homeRuns > awayRuns ? "W" : "L" }
    return "L"
}

/// Plain-text rendering of the title, with team abbreviations in place of logos.
func makeTitle(for state: GameState, lastKnown: String = "", selectedTeamId: Int = defaultTeamId) -> String {
    guard let segments = titleSegments(for: state, selectedTeamId: selectedTeamId) else { return lastKnown }
    return segments.map { segment -> String in
        switch segment {
        case .separator:      return "│"
        case .dot:            return " · "
        case .text(let s):    return s
        case .team(let id):   return mlbAbbreviation(for: id)
        }
    }.joined()
}

private func matchup(_ selected: Int, _ opponent: Int, _ isHome: Bool) -> [TitleSegment] {
    [.separator, .text(" "), .team(selected), .text(isHome ? " vs " : " @ "), .team(opponent)]
}

private func score(_ awayId: Int, _ awayRuns: Int, _ homeId: Int, _ homeRuns: Int) -> [TitleSegment] {
    [.separator, .text(" "), .team(awayId), .text(" \(awayRuns) – \(homeRuns) "), .team(homeId)]
}

let titleTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "h:mm a"
    f.timeZone = .current
    return f
}()

let titleDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "M/d"
    f.timeZone = .current
    return f
}()
