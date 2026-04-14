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

    private let rankLabel      = NSTextField(labelWithString: "")
    private let logoView       = NSImageView()
    private let nameLabel      = NSTextField(labelWithString: "")
    private let gameInfoLabel  = NSTextField(labelWithString: "—")
    private let recordLabel    = NSTextField(labelWithString: "—")

    private var nameFont: NSFont {
        isSelected
            ? NSFont.boldSystemFont(ofSize: 13)
            : NSFont.systemFont(ofSize: 13)
    }

    // MARK: - Init

    init(teamId: Int) {
        self.teamId = teamId
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
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
        gameInfoLabel.alignment = .right

        // Record
        recordLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        recordLabel.textColor = .secondaryLabelColor
        recordLabel.alignment = .right

        for field in [rankLabel, nameLabel, gameInfoLabel, recordLabel] {
            field.isEditable = false
            field.isSelectable = false
            field.isBordered = false
            field.drawsBackground = false
        }

        for v in [rankLabel, logoView, nameLabel, gameInfoLabel, recordLabel] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }

        // Layout (column width = 280pt)
        // rank: 8 leading, 18 wide
        // logo: 4 gap, 16 wide
        // name: 4 gap, flexible (up to game info)
        // gameInfo: 90 wide, 6 gap before record
        // record: 38 wide, 8 trailing
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

            gameInfoLabel.trailingAnchor.constraint(equalTo: recordLabel.leadingAnchor, constant: -6),
            gameInfoLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            gameInfoLabel.widthAnchor.constraint(equalToConstant: 90),

            recordLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            recordLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            recordLabel.widthAnchor.constraint(equalToConstant: 38),
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
            recordLabel.stringValue = "\(r.wins)-\(r.losses)"
            recordLabel.textColor = .secondaryLabelColor
        } else {
            recordLabel.stringValue = "—"
            recordLabel.textColor = .tertiaryLabelColor
        }
    }

    func setGameStatus(_ status: TodayGameStatus) {
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
