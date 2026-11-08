import Cocoa
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let fetcher = GameFetcher()
    private var timer: Timer?
    private var latestStandings: TeamRecords?
    private var lastState: GameState?

    // Popover state
    private var popover: NSPopover?
    private var standingsVC: StandingsViewController?
    private var eventMonitor: Any?
    private var latestTodayGames: [Int: TodayGameStatus]?
    private var latestTodayGamesTimestamp: Date?
    private var todayGamesTimer: Timer?

    // Error resilience: the failure marker appears only after this many
    // consecutive failed fetches, so transient errors stay invisible.
    private let failureThreshold = 3
    private var consecutiveFailures = 0
    private let errorMarker = " ·?"

    private static let logoSize: CGFloat = 18

    // `--demo` renders fixed sample data instead of polling (see demoState()).
    private var isDemo = false

    // MARK: - Team Selection (UserDefaults)

    private var selectedTeamId: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: "selectedTeamId")
            return v == 0 ? defaultTeamId : v   // 0 = key absent
        }
        set { UserDefaults.standard.set(newValue, forKey: "selectedTeamId") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Show the stored team's logo before the first fetch returns.
        fetcher.teamId = selectedTeamId
        statusItem.button?.attributedTitle = makeTeamPlaceholder(for: selectedTeamId)

        // Wire up popover toggle — do NOT set statusItem.menu (would intercept clicks).
        statusItem.button?.action = #selector(togglePopover(_:))
        statusItem.button?.target = self

        // Kick off initial data fetches.
        fetchAndRebuildStandings()

        // Re-sync immediately when the Mac wakes from sleep (timer drift).
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification, object: nil)

        // Redraw the status item as team logos finish downloading.
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleLogoLoaded),
            name: TeamLogoStore.didLoadLogo, object: nil)

        if let demo = demoState() {
            // `--demo live|final|upcoming` renders a fixed sample instead of
            // polling, for screenshots and layout work out of season. The
            // popover gets one team in every game status; standings stay real.
            isDemo = true
            latestTodayGames = demoTodayGames()
            apply(state: demo)
            return
        }

        refresh()
    }

    /// Sample statuses for the popover's game column: live games in both
    /// halves of an inning, upcoming, postponed and next-game rows, plus
    /// teams with no game, so every layout the column can show is visible.
    private func demoTodayGames() -> [Int: TodayGameStatus] {
        let cal = Calendar.current
        let tonight = cal.date(bySettingHour: 19, minute: 5, second: 0, of: Date()) ?? Date()
        let friday = cal.date(byAdding: .day, value: 3, to: tonight) ?? tonight
        return [
            111: .live(opponentAbbr: "NYY", isHome: false, myRuns: 3, theirRuns: 5, inning: 7, isTopInning: true),
            147: .live(opponentAbbr: "BOS", isHome: true,  myRuns: 5, theirRuns: 3, inning: 7, isTopInning: true),
            119: .live(opponentAbbr: "SF",  isHome: true,  myRuns: 2, theirRuns: 2, inning: 4, isTopInning: false),
            137: .live(opponentAbbr: "LAD", isHome: false, myRuns: 2, theirRuns: 2, inning: 4, isTopInning: false),
            110: .upcoming(opponentAbbr: "TB",  isHome: true,  time: tonight),
            139: .upcoming(opponentAbbr: "BAL", isHome: false, time: tonight),
            144: .upcoming(opponentAbbr: "PHI", isHome: true,  time: tonight),
            143: .upcoming(opponentAbbr: "ATL", isHome: false, time: tonight),
            117: .upcoming(opponentAbbr: "SEA", isHome: true,  time: tonight),
            136: .upcoming(opponentAbbr: "HOU", isHome: false, time: tonight),
            112: .postponed,
            138: .postponed,
            116: .nextGame(opponentAbbr: "CLE", isHome: true,  date: friday),
            114: .nextGame(opponentAbbr: "DET", isHome: false, date: friday),
            158: .nextGame(opponentAbbr: "CHC", isHome: true,  date: friday),
        ]
    }

    private func demoState() -> GameState? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--demo"), i + 1 < args.count else { return nil }
        let opponent = 111 // Red Sox
        switch args[i + 1] {
        case "live":
            return .live(awayAbbr: "BOS", awayId: opponent, awayRuns: 3,
                         homeAbbr: "NYY", homeId: selectedTeamId, homeRuns: 5,
                         inning: 7, isTopInning: true)
        case "final":
            return .final_(awayAbbr: "BOS", awayId: opponent, awayRuns: 3,
                           homeAbbr: "NYY", homeId: selectedTeamId, homeRuns: 5)
        case "upcoming":
            return .upcoming(opponentId: opponent, isHome: true,
                             time: Calendar.current.date(bySettingHour: 19, minute: 5, second: 0, of: Date()) ?? Date())
        default:
            return nil
        }
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
        removeEventMonitor()
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak pop] _ in
            pop?.performClose(nil)
        }

        guard !isDemo else { return }

        // Live-refresh timer: fires every 30s while popover is open.
        todayGamesTimer?.invalidate()
        todayGamesTimer = Timer.scheduledTimer(timeInterval: 30, target: self,
                                               selector: #selector(fetchAndUpdateTodayGames),
                                               userInfo: nil, repeats: true)

        // Fetch fresh games if nil or stale (>= 60s old).
        let isStale = latestTodayGamesTimestamp.map { Date().timeIntervalSince($0) >= 60 } ?? true
        if isStale { fetchAndUpdateTodayGames() }
    }

    private func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
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
        lastState = nil
        statusItem.button?.attributedTitle = makeTeamPlaceholder(for: newId)

        refresh()
    }

    // MARK: - Polling

    @objc func handleWake() {
        refresh()
        fetchAndRebuildStandings()
    }

    @objc private func handleLogoLoaded() {
        if let state = lastState {
            apply(state: state)
        } else {
            statusItem.button?.attributedTitle = makeTeamPlaceholder(for: selectedTeamId)
        }
        if consecutiveFailures >= failureThreshold { appendErrorMarker() }
    }

    @objc func refresh() {
        timer?.invalidate()
        fetcher.fetchCurrentState { [weak self] state in
            guard let self else { return }
            if case .error = state {
                self.consecutiveFailures += 1
                if self.consecutiveFailures >= self.failureThreshold { self.appendErrorMarker() }
            } else {
                self.consecutiveFailures = 0
                self.apply(state: state)
                if case .final_ = state { self.fetchAndRebuildStandings() }
            }
            self.scheduleNextRefresh(for: state)
        }
    }

    private func appendErrorMarker() {
        guard let current = statusItem.button?.attributedTitle,
              !current.string.hasSuffix(errorMarker) else { return }
        let mutable = NSMutableAttributedString(attributedString: current)
        mutable.append(NSAttributedString(string: errorMarker))
        statusItem.button?.attributedTitle = mutable
    }

    private func scheduleNextRefresh(for state: GameState) {
        timer?.invalidate()
        let interval: TimeInterval
        switch state {
        case .live:
            interval = 30
        case .upcoming(_, _, let time):
            interval = Date().distance(to: time) <= 30 * 60 ? 60 : 5 * 60
        case .error:
            // Retry soon so a single dropped request does not stall a live game.
            interval = 60
        default:
            interval = 5 * 60
        }
        timer = Timer.scheduledTimer(timeInterval: interval, target: self,
                                     selector: #selector(refresh), userInfo: nil, repeats: false)
    }

    // MARK: - Login item

    @objc func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let service = SMAppService.mainApp
        if service.status == .enabled {
            try? service.unregister()
        } else {
            try? service.register()
            if service.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        }
        sender.state = service.status == .enabled ? .on : .off
    }

    // MARK: - Standings

    private func currentSeason() -> Int {
        Calendar.current.component(.year, from: Date())
    }

    private func fetchAndRebuildStandings() {
        fetcher.fetchStandings(season: currentSeason()) { [weak self] result in
            guard let self, case .success(let records) = result, !records.isEmpty else { return }
            self.latestStandings = records
            self.standingsVC?.update(standings: records)
        }
    }

    // MARK: - Today's games (popover)

    @objc func fetchAndUpdateTodayGames() {
        fetcher.fetchTodayAllGames { [weak self] games in
            guard let self else { return }
            if !games.isEmpty {
                self.latestTodayGames = games
                self.latestTodayGamesTimestamp = Date()
            }
            if let latest = self.latestTodayGames {
                self.standingsVC?.update(games: latest)
            }
        }
    }

    // MARK: - Display

    private func apply(state: GameState) {
        lastState = state
        if let title = makeAttributedTitle(for: state) {
            statusItem.button?.attributedTitle = title
        }
    }

    /// "[logo] CODE" string shown at launch or immediately after a team switch,
    /// before the first fetch for the new team completes.
    private func makeTeamPlaceholder(for teamId: Int) -> NSAttributedString {
        let s = NSMutableAttributedString()
        if let img = logoImage(for: teamId) {
            s.append(logoAttachment(img))
            s.append(textAtt(" "))
        }
        s.append(textAtt(mlbAbbreviation(for: teamId)))
        return s
    }

    /// Navy in light mode, where it reads well on the translucent menu bar;
    /// the system label colour in dark mode, where navy would vanish.
    private static let statusTextColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? .labelColor
            : NSColor(red: 12/255, green: 35/255, blue: 64/255, alpha: 1)
    }

    private func textAtt(_ str: String) -> NSAttributedString {
        NSAttributedString(string: str, attributes: [.foregroundColor: Self.statusTextColor])
    }

    private func boldTextAtt(_ str: String) -> NSAttributedString {
        NSAttributedString(string: str, attributes: [
            .foregroundColor: Self.statusTextColor,
            .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        ])
    }

    private func logoAttachment(_ img: NSImage) -> NSAttributedString {
        let att = NSTextAttachment()
        att.image = img
        att.bounds = CGRect(x: 0, y: -3, width: Self.logoSize, height: Self.logoSize)
        return NSAttributedString(attachment: att)
    }

    /// Renders the shared title layout with logos (see TitleFormatter.swift).
    /// Returns nil for `.error`, where the current title is kept.
    private func makeAttributedTitle(for state: GameState) -> NSAttributedString? {
        guard let segments = titleSegments(for: state, selectedTeamId: selectedTeamId) else { return nil }
        let s = NSMutableAttributedString()
        for segment in segments {
            switch segment {
            case .separator:
                s.append(boldTextAtt("│"))
            case .dot:
                s.append(boldTextAtt(" · "))
            case .text(let str):
                s.append(textAtt(str))
            case .team(let teamId):
                // Falls back to the abbreviation until the logo has downloaded.
                if let img = logoImage(for: teamId) {
                    s.append(logoAttachment(img))
                } else {
                    s.append(textAtt(mlbAbbreviation(for: teamId)))
                }
            }
        }
        return s
    }
}

// MARK: - NSPopoverDelegate

extension AppDelegate: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        // A popover closing late must not tear down one that just opened.
        guard (notification.object as? NSPopover) === popover else { return }
        todayGamesTimer?.invalidate()
        todayGamesTimer = nil
        removeEventMonitor()
        standingsVC = nil
        popover = nil
    }
}
