import Cocoa
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let fetcher = GameFetcher()
    private var timer: Timer?
    private var latestStandings: TeamRecords?

    // Popover state
    private var popover: NSPopover?
    private var standingsVC: StandingsViewController?
    private var eventMonitor: Any?
    private var latestTodayGames: [Int: TodayGameStatus]?
    private var latestTodayGamesTimestamp: Date?
    private var todayGamesTimer: Timer?

    // Error resilience: only show .error state after 3 consecutive failures.
    private var consecutiveFailures = 0

    // MARK: - Team Selection (UserDefaults)

    private var selectedTeamId: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: "selectedTeamId")
            return v == 0 ? 147 : v   // 0 = key absent; default to Yankees
        }
        set { UserDefaults.standard.set(newValue, forKey: "selectedTeamId") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("🚀 On Deck App launched")

        NSApp.setActivationPolicy(.accessory)
        NSLog("📱 Activation policy set to accessory")

        // Show the stored team's logo before the first fetch returns.
        fetcher.teamId = selectedTeamId
        statusItem.button?.attributedTitle = makeTeamPlaceholder(for: selectedTeamId)
        NSLog("✅ Status item initialised for teamId: \(selectedTeamId)")

        // Wire up popover toggle — do NOT set statusItem.menu (would intercept clicks).
        statusItem.button?.action = #selector(togglePopover(_:))
        statusItem.button?.target = self

        // Kick off initial data fetches.
        fetchAndRebuildStandings()

        // Re-sync immediately when the Mac wakes from sleep (timer drift).
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification, object: nil)

        NSLog("🔄 Starting initial refresh...")
        refresh()
    }

    // MARK: - Popover

    @objc func togglePopover(_ sender: NSStatusBarButton) {
        if let pop = popover, pop.isShown {
            pop.performClose(sender)
        } else {
            openPopover(sender)
        }
    }

    private func openPopover(_ sender: NSStatusBarButton) {
        let vc = StandingsViewController(
            selectedTeamId: selectedTeamId,
            standings: latestStandings,
            games: latestTodayGames,
            settingsMenu: buildSettingsMenu()
        )
        vc.onSelectTeam = { [weak self] teamId in
            self?.selectTeam(teamId: teamId)
        }

        let pop = NSPopover()
        pop.contentViewController = vc
        pop.behavior = .transient
        pop.delegate = self
        pop.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)

        popover = pop
        standingsVC = vc

        // Close the popover when the user clicks outside it in any other app or on
        // the desktop. NSPopover.behavior = .transient handles in-app clicks; the
        // global monitor covers Finder, other apps, and the desktop where .transient
        // doesn't reliably fire for .accessory-policy processes.
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak pop] _ in
            pop?.performClose(nil)
        }

        // Live-refresh timer: fires every 30s while popover is open.
        todayGamesTimer?.invalidate()
        todayGamesTimer = Timer.scheduledTimer(timeInterval: 30, target: self,
                                               selector: #selector(fetchAndUpdateTodayGames),
                                               userInfo: nil, repeats: true)

        // Fetch fresh games if nil or stale (>= 60s old).
        let isStale = latestTodayGamesTimestamp.map { Date().timeIntervalSince($0) >= 60 } ?? true
        if isStale { fetchAndUpdateTodayGames() }
    }

    // MARK: - Settings menu

    private func buildSettingsMenu() -> NSMenu {
        let m = NSMenu()

        let loginItem = NSMenuItem(title: "Launch at Login",
                                   action: #selector(toggleLaunchAtLogin(_:)),
                                   keyEquivalent: "")
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        m.addItem(loginItem)

        m.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit On Deck App",
                                  action: #selector(NSApplication.terminate(_:)),
                                  keyEquivalent: "q")
        m.addItem(quitItem)

        return m
    }

    // MARK: - Team Selection

    func selectTeam(teamId newId: Int) {
        guard newId != selectedTeamId else { return }
        defer { popover?.performClose(nil) }

        selectedTeamId = newId
        fetcher.teamId = newId

        // Show new team's logo immediately; don't let a stale score linger.
        statusItem.button?.attributedTitle = makeTeamPlaceholder(for: newId)

        refresh()
    }

    // MARK: - Polling

    @objc func handleWake() {
        refresh()
        fetchAndRebuildStandings()
    }

    @objc func refresh() {
        timer?.invalidate()
        fetcher.fetchCurrentState { [weak self] state in
            guard let self else { return }
            print("[GameFetcher]", state)

            DispatchQueue.main.async {
                if case .error = state {
                    self.consecutiveFailures += 1
                    if self.consecutiveFailures < 3 {
                        self.scheduleNextRefresh(for: state)
                        return
                    }
                    if let current = self.statusItem.button?.attributedTitle,
                       !current.string.hasSuffix(" ·?") {
                        let mutable = NSMutableAttributedString(attributedString: current)
                        mutable.append(NSAttributedString(string: " ·?"))
                        self.statusItem.button?.attributedTitle = mutable
                    }
                    self.scheduleNextRefresh(for: state)
                } else {
                    self.consecutiveFailures = 0
                    self.apply(state: state)
                    self.scheduleNextRefresh(for: state)

                    if case .final_ = state {
                        self.fetchAndRebuildStandings()
                    }
                }
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

    // MARK: - Login item

    @objc func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
            sender.state = .off
        } else {
            try? SMAppService.mainApp.register()
            sender.state = .on
        }
    }

    // MARK: - Standings

    private func currentSeason() -> Int {
        Calendar.current.component(.year, from: Date())
    }

    private func fetchAndRebuildStandings() {
        fetcher.fetchStandings(season: currentSeason()) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                if case .success(let records) = result {
                    self.latestStandings = records
                    self.standingsVC?.update(standings: records)
                }
            }
        }
    }

    // MARK: - Today's games (popover)

    @objc func fetchAndUpdateTodayGames() {
        fetcher.fetchTodayAllGames { [weak self] games in
            guard let self else { return }
            DispatchQueue.main.async {
                if !games.isEmpty {
                    self.latestTodayGames = games
                    self.latestTodayGamesTimestamp = Date()
                }
                if let latest = self.latestTodayGames {
                    self.standingsVC?.update(games: latest)
                }
            }
        }
    }

    // MARK: - Display

    private func apply(state: GameState) {
        statusItem.button?.attributedTitle = makeAttributedTitle(for: state)
    }

    /// Composites an image over a dark rounded-rect background.
    private func withDarkBackground(_ img: NSImage, size: NSSize) -> NSImage {
        let result = NSImage(size: size)
        result.lockFocus()
        let rect = NSRect(origin: .zero, size: size)
        NSColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
        let logoRect = NSRect(x: 1, y: 1, width: size.width - 2, height: size.height - 2)
        img.draw(in: logoRect)
        result.unlockFocus()
        return result
    }

    /// "[logo] CODE" string shown at launch or immediately after a team switch,
    /// before the first fetch for the new team completes.
    private func makeTeamPlaceholder(for teamId: Int) -> NSAttributedString {
        let s = NSMutableAttributedString()
        if let img = logoImage(for: teamId) {
            let att = NSTextAttachment()
            att.image = img
            att.bounds = CGRect(x: 0, y: -3, width: 18, height: 18)
            s.append(NSAttributedString(attachment: att))
            s.append(blueAtt(" "))
        }
        s.append(blueAtt(espnCode(for: teamId).uppercased()))
        return s
    }

    /*
     Menu bar display format (logos replace team abbreviations):

       Upcoming:  [user-logo] vs [opp-logo] · 7:05 PM
       Live:      [away-logo] 3 – 1 [home-logo] · ↑7
       Final:     [away-logo] 3 – 1 [home-logo] · W
       Postponed: [user-logo] vs [opp-logo] · PPD
       Next game: [user-logo] vs [opp-logo] · Fri 4/5 7:05 PM
       Off season:[user-logo] · Off Season
    */
    private static let yankeeBlue = NSColor(red: 12/255, green: 35/255, blue: 64/255, alpha: 1)

    private func blueAtt(_ str: String) -> NSAttributedString {
        NSAttributedString(string: str, attributes: [.foregroundColor: Self.yankeeBlue])
    }

    private func boldBlueAtt(_ str: String) -> NSAttributedString {
        NSAttributedString(string: str, attributes: [
            .foregroundColor: Self.yankeeBlue,
            .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        ])
    }

    private func separatorAtt() -> NSAttributedString { boldBlueAtt("│") }
    private func dotAtt() -> NSAttributedString { boldBlueAtt(" · ") }

    private func makeAttributedTitle(for state: GameState) -> NSAttributedString {
        func logoAtt(for teamId: Int) -> NSAttributedString {
            guard let img = logoImage(for: teamId) else { return NSAttributedString() }
            let att = NSTextAttachment()
            att.image = img
            att.bounds = CGRect(x: 0, y: -3, width: 18, height: 18)
            return NSAttributedString(attachment: att)
        }

        let s = NSMutableAttributedString()

        switch state {
        case .upcoming(_, let opponentId, let isHome, let time):
            let timeStr = timeFormatter.string(from: time)
            s.append(separatorAtt())
            s.append(blueAtt(" "))
            s.append(logoAtt(for: selectedTeamId))
            s.append(blueAtt(isHome ? " vs " : " @ "))
            s.append(logoAtt(for: opponentId))
            s.append(dotAtt())
            s.append(blueAtt("\(timeStr) "))
            s.append(separatorAtt())

        case .live(_, let awayId, let awayRuns, _, let homeId, let homeRuns, let inning, let isTop):
            s.append(separatorAtt())
            s.append(blueAtt(" "))
            s.append(logoAtt(for: awayId))
            s.append(blueAtt(" \(awayRuns) – \(homeRuns) "))
            s.append(logoAtt(for: homeId))
            s.append(dotAtt())
            s.append(blueAtt("\(inning)\(isTop ? "↑" : "↓") "))
            s.append(separatorAtt())

        case .final_(_, let awayId, let awayRuns, _, let homeId, let homeRuns):
            let result: String
            if awayRuns == homeRuns {
                result = "T"
            } else if awayId == selectedTeamId {
                result = awayRuns > homeRuns ? "W" : "L"
            } else if homeId == selectedTeamId {
                result = homeRuns > awayRuns ? "W" : "L"
            } else {
                result = "L"
            }
            s.append(separatorAtt())
            s.append(blueAtt(" "))
            s.append(logoAtt(for: awayId))
            s.append(blueAtt(" \(awayRuns) – \(homeRuns) "))
            s.append(logoAtt(for: homeId))
            s.append(dotAtt())
            s.append(blueAtt("\(result) "))
            s.append(separatorAtt())

        case .postponed(_, let opponentId, let isHome):
            s.append(separatorAtt())
            s.append(blueAtt(" "))
            s.append(logoAtt(for: selectedTeamId))
            s.append(blueAtt(isHome ? " vs " : " @ "))
            s.append(logoAtt(for: opponentId))
            s.append(dotAtt())
            s.append(blueAtt("PPD "))
            s.append(separatorAtt())

        case .nextGame(_, let opponentId, let isHome, let date):
            let timeStr = timeFormatter.string(from: date)
            s.append(separatorAtt())
            s.append(blueAtt(" "))
            s.append(logoAtt(for: selectedTeamId))
            s.append(blueAtt(isHome ? " vs " : " @ "))
            s.append(logoAtt(for: opponentId))
            if Calendar.current.isDateInToday(date) {
                s.append(dotAtt())
                s.append(blueAtt("\(timeStr) "))
            } else {
                let dateStr = nextGameFormatter.string(from: date)
                s.append(dotAtt())
                s.append(blueAtt("\(dateStr)"))
                s.append(dotAtt())
                s.append(blueAtt("\(timeStr) "))
            }
            s.append(separatorAtt())

        case .offSeason:
            s.append(separatorAtt())
            s.append(blueAtt(" "))
            s.append(logoAtt(for: selectedTeamId))
            s.append(dotAtt())
            s.append(blueAtt("Off Season "))
            s.append(separatorAtt())

        case .error:
            return statusItem.button?.attributedTitle ?? NSAttributedString(string: "—")
        }

        return s
    }
}

// MARK: - NSPopoverDelegate

extension AppDelegate: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        todayGamesTimer?.invalidate()
        todayGamesTimer = nil
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        standingsVC = nil
        popover = nil
    }
}

// MARK: - Title formatting (pure; used by tests)

func makeTitle(for state: GameState, lastKnown: String = "NYY", selectedTeamId: Int = yankeesTeamId) -> String {
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
        } else if awayId == selectedTeamId {
            result = awayRuns > homeRuns ? "W" : "L"
        } else if homeId == selectedTeamId {
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
        let timeStr = timeFormatter.string(from: date)
        let suffix = Calendar.current.isDateInToday(date) ? " · \(timeStr)" : " · \(dateStr) · \(timeStr)"
        return isHome ? "vs \(teamAbbreviation(opp))\(suffix)"
                      : "@ \(teamAbbreviation(opp))\(suffix)"

    case .offSeason:
        return "\(espnCode(for: selectedTeamId).uppercased()) · Off Season"

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
    f.dateFormat = "M/d"
    f.timeZone = TimeZone.current
    return f
}()
