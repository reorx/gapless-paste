import AppKit
import GaplessPasteCore

/// 固定宽度的信息区，不参与菜单动作高亮。名称按实际布局宽度省略。
final class TransferSummaryView: NSView {
    static let menuWidth: CGFloat = 288
    private let title = NSTextField(labelWithString: "")
    private let symbol = NSImageView()
    private let content = NSTextField(labelWithString: "")
    private let direction = NSTextField(labelWithString: "")
    private let time = NSTextField(labelWithString: "")
    private let subtitle: NSStackView

    init() {
        subtitle = NSStackView(views: [content, direction, time])
        super.init(frame: NSRect(x: 0, y: 0, width: Self.menuWidth, height: 62))
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        title.textColor = .labelColor
        subtitle.orientation = .horizontal
        subtitle.spacing = 0
        for label in [content, direction, time] {
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            label.lineBreakMode = .byTruncatingMiddle
        }
        direction.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for label in [content, time] {
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        for view in [symbol, title, subtitle] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            symbol.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            symbol.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            symbol.widthAnchor.constraint(equalToConstant: 14),
            symbol.heightAnchor.constraint(equalToConstant: 16),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 38),
            title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(lessThanOrEqualTo: title.trailingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 5),
        ])
        setAccessibilityIdentifier("transfer-summary")
    }

    required init?(coder: NSCoder) { fatalError("unused") }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(_ state: TransferPresentation) {
        title.stringValue = state.title
        if let record = state.record {
            content.stringValue = record.content.label + " · "
            direction.stringValue = record.direction
            time.stringValue = record.finishedAt.map { " · " + DisplayFormatter.relativeTimeText(from: $0) } ?? ""
        } else {
            content.stringValue = ""
            direction.stringValue = state.subtitle()
            time.stringValue = ""
        }
        let name: String
        switch state.record?.outcome {
        case .running: name = state.record?.operation == .pullClipboard ? "arrow.down" : "arrow.up"
        case .success: name = "checkmark"
        case .failure, .partialSuccess: name = "exclamationmark"
        case nil: name = "clipboard"
        }
        symbol.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        setAccessibilityLabel(state.title + "，" + state.subtitle())
    }

    static func labelItem(_ text: String) -> NSMenuItem {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: menuWidth, height: 25))
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingMiddle
        label.frame = NSRect(x: 14, y: 4, width: menuWidth - 30, height: 17)
        view.addSubview(label)
        let item = NSMenuItem()
        item.isEnabled = false
        item.view = view
        return item
    }
}
