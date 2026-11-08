import Cocoa

final class TeamRowView: NSView {

    var onSelect: ((Int) -> Void)?

    private let teamId: Int
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    var isSelected: Bool = false {
        didSet {
            nameLabel.font = nameFont
            needsDisplay = true
        }
    }

    // MARK: - Subviews

    private let rankLabel     = NSTextField(labelWithString: "")
    private let logoView      = NSImageView()
    private let nameLabel     = NSTextField(labelWithString: "")
    let gameInfoLabel = NSTextField(labelWithString: "")
    private let winsLabel     = NSTextField(labelWithString: "")
    private let dashLabel     = NSTextField(labelWithString: "")
    private let lossesLabel   = NSTextField(labelWithString: "")

    // Stored so setGameStatus can collapse/expand the game info column.
    private var gameInfoWidthConstraint: NSLayoutConstraint?

    private var nameFont: NSFont {
        isSelected
            ? NSFont.boldSystemFont(ofSize: 13)
            : NSFont.systemFont(ofSize: 13)
    }

    // MARK: - Init

    static let rowWidth: CGFloat = 319

    init(teamId: Int) {
        self.teamId = teamId
        super.init(frame: NSRect(x: 0, y: 0, width: Self.rowWidth, height: 24))
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        // Rank
        rankLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        rankLabel.textColor = .tertiaryLabelColor
        rankLabel.alignment = .right

        // Logo
        logoView.imageScaling = .scaleProportionallyUpOrDown

        // Name
        nameLabel.font = nameFont
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail

        // Game info
        gameInfoLabel.font = NSFont.systemFont(ofSize: 11)
        gameInfoLabel.textColor = .secondaryLabelColor
        gameInfoLabel.alignment = .left

        // Wins / dash / losses (record, split into three fixed-width labels so
        // the "–" separator always sits at the same X position regardless of
        // whether win/loss counts are single- or double-digit).
        winsLabel.font   = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        winsLabel.textColor = .secondaryLabelColor
        winsLabel.alignment = .right

        dashLabel.font   = NSFont.systemFont(ofSize: 11)
        dashLabel.textColor = .secondaryLabelColor
        dashLabel.alignment = .center

        lossesLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        lossesLabel.textColor = .secondaryLabelColor
        lossesLabel.alignment = .left

        for field in [rankLabel, nameLabel, gameInfoLabel, winsLabel, dashLabel, lossesLabel] {
            field.isEditable = false
            field.isSelectable = false
            field.isBordered = false
            field.drawsBackground = false
        }

        for v in [rankLabel, logoView, nameLabel, gameInfoLabel,
                  winsLabel, dashLabel, lossesLabel] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }

        // Layout (column width = 319pt)
        // rank:     8pt leading, 18pt wide
        // logo:     4pt gap, 16pt wide
        // name:     4pt gap, flexible up to gameInfo
        // gameInfo: trailing pinned to wins.leading – 6; width = 0 when no game, 105 otherwise
        // wins:     20pt, right-aligned  ─┐
        // dash:      8pt, centered        ├─ record area 48pt, dash always at same X
        // losses:   20pt, left-aligned  ──┘
        // margin:   8pt trailing

        let gameInfoWidth = gameInfoLabel.widthAnchor.constraint(equalToConstant: 0)
        gameInfoWidthConstraint = gameInfoWidth

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 24),

            rankLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            rankLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            rankLabel.widthAnchor.constraint(equalToConstant: 18),

            logoView.leadingAnchor.constraint(equalTo: rankLabel.trailingAnchor, constant: 4),
            logoView.centerYAnchor.constraint(equalTo: centerYAnchor),
            logoView.widthAnchor.constraint(equalToConstant: 16),
            logoView.heightAnchor.constraint(equalToConstant: 16),

            nameLabel.leadingAnchor.constraint(equalTo: logoView.trailingAnchor, constant: 4),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: gameInfoLabel.leadingAnchor, constant: -4),

            gameInfoLabel.trailingAnchor.constraint(equalTo: winsLabel.leadingAnchor, constant: -6),
            gameInfoLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            gameInfoWidth,

            winsLabel.trailingAnchor.constraint(equalTo: dashLabel.leadingAnchor),
            winsLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            winsLabel.widthAnchor.constraint(equalToConstant: 20),

            dashLabel.trailingAnchor.constraint(equalTo: lossesLabel.leadingAnchor),
            dashLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            dashLabel.widthAnchor.constraint(equalToConstant: 8),

            lossesLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            lossesLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            lossesLabel.widthAnchor.constraint(equalToConstant: 20),
        ])
    }

    // MARK: - Data updates

    func setLogo(_ image: NSImage?) {
        logoView.image = image
    }

    func setName(_ name: String) {
        nameLabel.stringValue = name
    }

    func setRank(_ rank: Int?) {
        rankLabel.stringValue = rank.map { "\($0)." } ?? ""
    }

    func setRecord(_ record: (wins: Int, losses: Int)?) {
        if let r = record {
            winsLabel.stringValue   = "\(r.wins)"
            dashLabel.stringValue   = "–"
            lossesLabel.stringValue = "\(r.losses)"
            winsLabel.textColor   = .secondaryLabelColor
            dashLabel.textColor   = .secondaryLabelColor
            lossesLabel.textColor = .secondaryLabelColor
        } else {
            winsLabel.stringValue   = "—"
            dashLabel.stringValue   = ""
            lossesLabel.stringValue = ""
            winsLabel.textColor   = .tertiaryLabelColor
        }
    }

    func setGameStatus(_ status: TodayGameStatus) {
        switch status {
        case .noGame, .final_:
            // Collapse game info — final scores are not shown; next game (if any)
            // will be delivered as a .nextGame status by the fetcher instead.
            gameInfoLabel.isHidden = true
            gameInfoWidthConstraint?.constant = 0
            return
        default:
            break
        }

        gameInfoLabel.isHidden = false
        gameInfoWidthConstraint?.constant = 105

        let str = gameInfoString(for: status)
        if case .live = status, str.hasPrefix("●") {
            // Color the live bullet green, rest in secondaryLabelColor
            let attr = NSMutableAttributedString()
            attr.append(NSAttributedString(string: "●", attributes: [
                .foregroundColor: NSColor.systemGreen,
                .font: NSFont.systemFont(ofSize: 11)
            ]))
            attr.append(NSAttributedString(string: String(str.dropFirst()), attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: 11)
            ]))
            gameInfoLabel.attributedStringValue = attr
        } else {
            gameInfoLabel.stringValue = str
            gameInfoLabel.textColor = .secondaryLabelColor
        }
    }

    // MARK: - Hover and selection

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingArea.map(removeTrackingArea)
        let area = NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?(teamId)
    }

    override func draw(_ dirtyRect: NSRect) {
        if isSelected {
            NSColor.selectedContentBackgroundColor.withAlphaComponent(0.2).setFill()
            bounds.fill()
        } else if isHovered {
            NSColor.controlAccentColor.withAlphaComponent(0.08).setFill()
            bounds.fill()
        }
        super.draw(dirtyRect)
    }
}
