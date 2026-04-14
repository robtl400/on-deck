import Cocoa

final class StandingsViewController: NSViewController {

    // MARK: - Configuration

    var onSelectTeam: ((Int) -> Void)?

    private let selectedTeamId: Int
    private var latestStandings: TeamRecords?
    private var latestGames: [Int: TodayGameStatus]?
    private let settingsMenu: NSMenu

    // MARK: - View registries (for in-place updates and reordering)

    private var rowViews: [Int: TeamRowView] = [:]
    private var divisionTeamStacks: [Int: NSStackView] = [:]  // keyed by MLBDivision.id

    // MARK: - Init

    init(selectedTeamId: Int,
         standings: TeamRecords?,
         games: [Int: TodayGameStatus]?,
         settingsMenu: NSMenu) {
        self.selectedTeamId = selectedTeamId
        self.latestStandings = standings
        self.latestGames = games
        self.settingsMenu = settingsMenu
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var preferredContentSize: NSSize {
        get { NSSize(width: 560, height: 700) }
        set { }
    }

    // MARK: - View lifecycle

    override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: preferredContentSize))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildLayout()
    }

    // MARK: - Layout

    private func buildLayout() {
        let headerHeight: CGFloat = 32

        // ── Header bar ──────────────────────────────────────────────────
        let header = makeHeaderBar()
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)

        // ── Vertical divider between columns ────────────────────────────
        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.separatorColor.cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(divider)

        // ── Column scroll views ──────────────────────────────────────────
        let alDivisions = Array(mlbDivisions[0..<3])   // AL East, AL Central, AL West
        let nlDivisions = Array(mlbDivisions[3..<6])   // NL East, NL Central, NL West

        let leftScroll  = makeColumnScrollView(divisions: alDivisions)
        let rightScroll = makeColumnScrollView(divisions: nlDivisions)
        leftScroll.translatesAutoresizingMaskIntoConstraints  = false
        rightScroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(leftScroll)
        view.addSubview(rightScroll)

        NSLayoutConstraint.activate([
            // Header
            header.topAnchor.constraint(equalTo: view.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: headerHeight),

            // Left scroll
            leftScroll.topAnchor.constraint(equalTo: header.bottomAnchor),
            leftScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            leftScroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            leftScroll.widthAnchor.constraint(equalToConstant: 280),

            // Divider
            divider.topAnchor.constraint(equalTo: header.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: leftScroll.trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),

            // Right scroll
            rightScroll.topAnchor.constraint(equalTo: header.bottomAnchor),
            rightScroll.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            rightScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rightScroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Header bar (32pt)

    private func makeHeaderBar() -> NSView {
        let bar = NSView()
        bar.wantsLayer = true

        // "AMERICAN LEAGUE" label — centered in left 280pt
        let alLabel = makeLeagueLabel("AMERICAN LEAGUE")
        alLabel.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(alLabel)

        // "NATIONAL LEAGUE" label — centered in middle 244pt
        let nlLabel = makeLeagueLabel("NATIONAL LEAGUE")
        nlLabel.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(nlLabel)

        // Gear button — 36pt right edge
        let gear = NSButton()
        gear.bezelStyle = .inline
        gear.isBordered = false
        gear.image = NSImage(systemSymbolName: "gear", accessibilityDescription: "Settings")
        gear.image?.isTemplate = true
        gear.contentTintColor = .secondaryLabelColor
        gear.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        gear.target = self
        gear.action = #selector(gearClicked(_:))
        gear.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(gear)

        // 1pt bottom border
        let border = NSView()
        border.wantsLayer = true
        border.layer?.backgroundColor = NSColor.separatorColor.cgColor
        border.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(border)

        NSLayoutConstraint.activate([
            alLabel.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            alLabel.widthAnchor.constraint(equalToConstant: 280),
            alLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor),

            nlLabel.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 280),
            nlLabel.widthAnchor.constraint(equalToConstant: 244),
            nlLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor),

            gear.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -2),
            gear.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            gear.widthAnchor.constraint(equalToConstant: 36),

            border.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            border.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            border.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            border.heightAnchor.constraint(equalToConstant: 1),
        ])

        return bar
    }

    private func makeLeagueLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .labelColor
        label.alignment = .center
        return label
    }

    // MARK: - Column scroll view

    private func makeColumnScrollView(divisions: [MLBDivision]) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false

        for division in divisions {
            // Division header (28pt: 8pt top padding + 20pt content)
            let headerView = makeDivisionHeader(division.name)
            stack.addArrangedSubview(headerView)
            NSLayoutConstraint.activate([
                headerView.widthAnchor.constraint(equalToConstant: 279),
            ])

            // Per-division team stack — stored so update(standings:) can reorder it.
            let teamStack = NSStackView()
            teamStack.orientation = .vertical
            teamStack.alignment = .leading
            teamStack.spacing = 0
            stack.addArrangedSubview(teamStack)
            NSLayoutConstraint.activate([
                teamStack.widthAnchor.constraint(equalToConstant: 279),
            ])
            divisionTeamStacks[division.id] = teamStack

            // Team rows sorted by win %
            let sortedIds = teamsSortedByWinPct(in: division, standings: latestStandings)
            for (index, teamId) in sortedIds.enumerated() {
                let row = makeTeamRow(teamId: teamId, rank: index + 1)
                teamStack.addArrangedSubview(row)
                NSLayoutConstraint.activate([
                    row.widthAnchor.constraint(equalToConstant: 279),
                ])
                rowViews[teamId] = row
            }
        }

        // Clip view / document view setup
        let clipView = NSClipView()
        clipView.documentView = stack
        clipView.drawsBackground = false
        scroll.contentView = clipView

        // Pin stack width to scroll width and let it grow vertically
        scroll.documentView = stack
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: clipView.topAnchor),
        ])

        return scroll
    }

    // MARK: - Division header view (28pt)

    private func makeDivisionHeader(_ name: String) -> NSView {
        let container = NSView()

        let label = NSTextField(labelWithString: "")
        let kern: [NSAttributedString.Key: Any] = [
            .kern: 0.8,
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        label.attributedStringValue = NSAttributedString(string: name.uppercased(), attributes: kern)
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 28),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
        ])

        return container
    }

    // MARK: - Team row

    private func makeTeamRow(teamId: Int, rank: Int) -> TeamRowView {
        let row = TeamRowView(teamId: teamId)
        row.setName(teamNickname(for: teamId))
        row.setLogo(logoImage(for: teamId, size: NSSize(width: 16, height: 16)))
        row.isSelected = (teamId == selectedTeamId)

        // Rank (shown only when standings available)
        if latestStandings != nil {
            row.setRank(rank)
        }

        // W-L record
        row.setRecord(latestStandings?[teamId])

        // Today's game status
        let status = latestGames?[teamId] ?? .noGame
        row.setGameStatus(status)

        row.onSelect = { [weak self] tid in
            self?.onSelectTeam?(tid)
        }

        return row
    }

    // MARK: - In-place data updates

    func update(games: [Int: TodayGameStatus]) {
        latestGames = games
        for (teamId, row) in rowViews {
            let status = games[teamId] ?? .noGame
            row.setGameStatus(status)
        }
    }

    func update(standings: TeamRecords) {
        latestStandings = standings
        for division in mlbDivisions {
            let sorted = teamsSortedByWinPct(in: division, standings: standings)
            guard let teamStack = divisionTeamStacks[division.id] else { continue }

            // Update data on each row.
            for (index, teamId) in sorted.enumerated() {
                rowViews[teamId]?.setRank(index + 1)
                rowViews[teamId]?.setRecord(standings[teamId])
            }

            // Reorder: strip all rows from arranged subviews, then re-add in sorted order.
            // removeArrangedSubview keeps the view in the hierarchy; addArrangedSubview
            // re-inserts it at the end, giving us a clean sort without rebuilding anything.
            for teamId in division.teamIds {
                rowViews[teamId].map { teamStack.removeArrangedSubview($0) }
            }
            for teamId in sorted {
                rowViews[teamId].map { teamStack.addArrangedSubview($0) }
            }
        }
    }

    // MARK: - Gear button

    @objc private func gearClicked(_ sender: NSButton) {
        guard let event = NSApp.currentEvent else { return }
        NSMenu.popUpContextMenu(settingsMenu, with: event, for: sender)
    }
}
