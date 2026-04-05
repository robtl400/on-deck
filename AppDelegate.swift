import Cocoa

@main
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let fetcher = GameFetcher()
    private var timer: Timer?

    // Error resilience: only show .error state after 3 consecutive failures.
    private var consecutiveFailures = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.prohibited)
        statusItem.button?.title = "NYY"

        let menu = NSMenu()
        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Yankees Menu Bar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        // Re-sync immediately when the Mac wakes from sleep (timer drift).
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(refresh),
            name: NSWorkspace.didWakeFromSleepNotification, object: nil)

        refresh()
    }

    // MARK: - Polling

    @objc func refresh() {
        timer?.invalidate()
        fetcher.fetchCurrentState { [weak self] state in
            guard let self else { return }
            print("[GameFetcher]", state) // ← verify data in Xcode console

            if case .error = state {
                self.consecutiveFailures += 1
                if self.consecutiveFailures < 3 {
                    // Keep displaying last known state; schedule retry at normal interval.
                    DispatchQueue.main.async { self.scheduleNextRefresh(for: state) }
                    return
                }
                // After 3+ failures, mark the displayed title as stale.
                DispatchQueue.main.async {
                    if let current = self.statusItem.button?.title, !current.hasSuffix(" ·?") {
                        self.statusItem.button?.title = current + " ·?"
                    }
                    self.scheduleNextRefresh(for: state)
                }
                return
            } else {
                self.consecutiveFailures = 0
            }

            DispatchQueue.main.async {
                self.apply(state: state)
                self.scheduleNextRefresh(for: state)
            }
        }
    }

    private func scheduleNextRefresh(for state: GameState) {
        timer?.invalidate()
        let interval: TimeInterval
        switch state {
        case .live:
            interval = 30
        case .upcoming(_, _, _, let time):
            interval = Date().distance(to: time) <= 30 * 60 ? 60 : 5 * 60
        default:
            interval = 5 * 60
        }
        timer = Timer.scheduledTimer(timeInterval: interval, target: self,
                                     selector: #selector(refresh), userInfo: nil, repeats: false)
    }

    // MARK: - Menu bar title

    private func apply(state: GameState) {
        statusItem.button?.title = makeTitle(for: state,
                                             lastKnown: statusItem.button?.title ?? "NYY")
    }
}

// MARK: - Title formatting (internal for testability)

func makeTitle(for state: GameState, lastKnown: String = "NYY") -> String {
    switch state {
    case .upcoming(let opp, _, let isHome, let time):
        let timeStr = timeFormatter.string(from: time)
        return isHome ? "vs \(teamAbbreviation(opp)) · \(timeStr)"
                      : "@ \(teamAbbreviation(opp)) · \(timeStr)"

    case .live(let awayAbbr, _, let awayRuns, let homeAbbr, _, let homeRuns, let inning, let isTop):
        let half = isTop ? "T" : "B"
        return "\(awayAbbr) \(awayRuns) – \(homeRuns) \(homeAbbr) · \(half)\(inning)"

    case .final_(let awayAbbr, let awayId, let awayRuns, let homeAbbr, let homeId, let homeRuns):
        let result: String
        if awayRuns == homeRuns {
            result = "T"
        } else if awayId == yankeesTeamId {
            result = awayRuns > homeRuns ? "W" : "L"
        } else if homeId == yankeesTeamId {
            result = homeRuns > awayRuns ? "W" : "L"
        } else {
            result = "L"
        }
        return "\(awayAbbr) \(awayRuns) – \(homeRuns) \(homeAbbr) · \(result)"

    case .postponed(let opp, _, let isHome):
        return isHome ? "vs \(teamAbbreviation(opp)) · PPD"
                      : "@ \(teamAbbreviation(opp)) · PPD"

    case .nextGame(let opp, _, let isHome, let date):
        let dateStr = nextGameFormatter.string(from: date)
        return isHome ? "vs \(teamAbbreviation(opp)) · \(dateStr)"
                      : "@ \(teamAbbreviation(opp)) · \(dateStr)"

    case .offSeason:
        return "NYY · Off Season"

    case .error:
        return lastKnown
    }
}

private let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "h:mm a"
    f.timeZone = TimeZone.current
    return f
}()

private let nextGameFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "EEE M/d"
    f.timeZone = TimeZone.current
    return f
}()
