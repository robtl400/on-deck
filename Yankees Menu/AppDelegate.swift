import Cocoa
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let fetcher = GameFetcher()
    private var timer: Timer?
    private var teamMenuItems: [NSMenuItem] = []

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
        NSLog("🚀 Yankees Menu app launched")

        NSApp.setActivationPolicy(.accessory)
        NSLog("📱 Activation policy set to accessory")
        NSLog("📱 Creating status item...")
        NSLog("🔍 Status item: \(statusItem)")
        NSLog("🔍 Status item button: \(String(describing: statusItem.button))")

        if statusItem.button == nil {
            NSLog("❌ Status item button is nil! This shouldn't happen...")
        }

        // Set the fetcher team and show the stored team's logo before the first
        // fetch returns, so no team ever sees "NYY" flash on launch (OV-6).
        fetcher.teamId = selectedTeamId
        statusItem.button?.attributedTitle = makeTeamPlaceholder(for: selectedTeamId)
        NSLog("✅ Status item initialised for teamId: \(selectedTeamId)")
        NSLog("📍 Status item isVisible: \(statusItem.isVisible)")

        let menu = NSMenu()

        // Change Team submenu — all 30 MLB teams, alphabetical.
        let changeTeamItem = NSMenuItem(title: "Change Team", action: nil, keyEquivalent: "")
        let teamSubmenu = NSMenu()
        let allTeams: [(name: String, id: Int)] = [
            ("Arizona Diamondbacks", 109),
            ("Atlanta Braves",       144),
            ("Athletics",            133),
            ("Baltimore Orioles",    110),
            ("Boston Red Sox",       111),
            ("Chicago Cubs",         112),
            ("Chicago White Sox",    145),
            ("Cincinnati Reds",      113),
            ("Cleveland Guardians",  114),
            ("Colorado Rockies",     115),
            ("Detroit Tigers",       116),
            ("Houston Astros",       117),
            ("Kansas City Royals",   118),
            ("Los Angeles Angels",   108),
            ("Los Angeles Dodgers",  119),
            ("Miami Marlins",        146),
            ("Milwaukee Brewers",    158),
            ("Minnesota Twins",      142),
            ("New York Mets",        121),
            ("New York Yankees",     147),
            ("Philadelphia Phillies",143),
            ("Pittsburgh Pirates",   134),
            ("San Diego Padres",     135),
            ("San Francisco Giants", 137),
            ("Seattle Mariners",     136),
            ("St. Louis Cardinals",  138),
            ("Tampa Bay Rays",       139),
            ("Texas Rangers",        140),
            ("Toronto Blue Jays",    141),
            ("Washington Nationals", 120),
        ]
        for (name, id) in allTeams {
            let item = NSMenuItem(title: name, action: #selector(selectTeam(_:)), keyEquivalent: "")
            item.target = self
            item.tag = id
            item.state = (id == selectedTeamId) ? .on : .off
            teamSubmenu.addItem(item)
            teamMenuItems.append(item)
        }
        changeTeamItem.submenu = teamSubmenu
        menu.addItem(changeTeamItem)
        menu.addItem(.separator())

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Yankees Menu Bar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        NSLog("🍔 Menu created with \(menu.items.count) items")

        // Re-sync immediately when the Mac wakes from sleep (timer drift).
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(refresh),
            name: NSWorkspace.didWakeNotification, object: nil)

        NSLog("🔄 Starting initial refresh...")
        refresh()
    }

    // MARK: - Team Selection

    @objc func selectTeam(_ sender: NSMenuItem) {
        let newId = sender.tag
        guard newId != selectedTeamId else { return }

        // Update checkmark state.
        teamMenuItems.forEach { $0.state = .off }
        sender.state = .on

        // Persist + propagate to fetcher (didSet clears activeGamePk so the next
        // poll does a fresh schedule lookup for the new team).
        selectedTeamId = newId
        fetcher.teamId = newId

        // Show new team's logo immediately; don't let a stale score linger (OV-8).
        statusItem.button?.attributedTitle = makeTeamPlaceholder(for: newId)

        refresh()
    }

    // MARK: - Polling

    @objc func refresh() {
        timer?.invalidate()
        fetcher.fetchCurrentState { [weak self] state in
            guard let self else { return }
            print("[GameFetcher]", state)

            DispatchQueue.main.async {
                if case .error = state {
                    self.consecutiveFailures += 1
                    if self.consecutiveFailures < 3 {
                        // Keep displaying last known state; schedule retry at normal interval.
                        self.scheduleNextRefresh(for: state)
                        return
                    }
                    // After 3+ failures, append stale indicator to current attributed title.
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

    // MARK: - Display

    private func apply(state: GameState) {
        statusItem.button?.attributedTitle = makeAttributedTitle(for: state)
    }

    /// Loads a team logo from Assets.xcassets at 18pt.
    /// Returns nil if the asset is missing; callers fall back to text-only display.
    private func logoImage(for teamId: Int) -> NSImage? {
        let code = espnCode(for: teamId)
        guard let img = NSImage(named: "logo-\(code)") else { return nil }
        let copy = img.copy() as! NSImage  // don't mutate the shared NSImage cache
        copy.isTemplate = false
        copy.size = NSSize(width: 18, height: 18)

        // CWS has a white-primary logo and ESPN has no dark/scoreboard variant for them.
        // Composite a dark rounded-rect background so the logo is visible on light menu bars.
        if teamId == 145 {
            return withDarkBackground(copy, size: NSSize(width: 20, height: 20))
        }
        return copy
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
            s.append(NSAttributedString(string: " "))
        }
        s.append(NSAttributedString(string: espnCode(for: teamId).uppercased()))
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
            s.append(logoAtt(for: selectedTeamId))
            s.append(NSAttributedString(string: isHome ? " vs " : " @ "))
            s.append(logoAtt(for: opponentId))
            s.append(NSAttributedString(string: " · \(timeStr)"))

        case .live(_, let awayId, let awayRuns, _, let homeId, let homeRuns, let inning, let isTop):
            s.append(logoAtt(for: awayId))
            s.append(NSAttributedString(string: " \(awayRuns) – \(homeRuns) "))
            s.append(logoAtt(for: homeId))
            s.append(NSAttributedString(string: " · \(isTop ? "↑" : "↓")\(inning)"))

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
            s.append(logoAtt(for: awayId))
            s.append(NSAttributedString(string: " \(awayRuns) – \(homeRuns) "))
            s.append(logoAtt(for: homeId))
            s.append(NSAttributedString(string: " · \(result)"))

        case .postponed(_, let opponentId, let isHome):
            s.append(logoAtt(for: selectedTeamId))
            s.append(NSAttributedString(string: isHome ? " vs " : " @ "))
            s.append(logoAtt(for: opponentId))
            s.append(NSAttributedString(string: " · PPD"))

        case .nextGame(_, let opponentId, let isHome, let date):
            let dateStr = nextGameFormatter.string(from: date)
            let timeStr = timeFormatter.string(from: date)
            s.append(logoAtt(for: selectedTeamId))
            s.append(NSAttributedString(string: isHome ? " vs " : " @ "))
            s.append(logoAtt(for: opponentId))
            s.append(NSAttributedString(string: " · \(dateStr) \(timeStr)"))

        case .offSeason:
            s.append(logoAtt(for: selectedTeamId))
            s.append(NSAttributedString(string: " · Off Season"))

        case .error:
            // Never called from apply(state:) — error path is handled in refresh().
            return statusItem.button?.attributedTitle ?? NSAttributedString(string: "—")
        }

        return s
    }
}

// MARK: - Title formatting (pure; used by tests — production display uses makeAttributedTitle(_:))

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
        return isHome ? "vs \(teamAbbreviation(opp)) · \(dateStr) \(timeStr)"
                      : "@ \(teamAbbreviation(opp)) · \(dateStr) \(timeStr)"

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
    f.dateFormat = "EEE M/d"
    f.timeZone = TimeZone.current
    return f
}()
