import AppKit
import GaplessPasteCore

// M3 拖拽上传（路径 C，UI 参考 Dropzone：面板锚定在图标正下方，目标平铺，拖入行高亮）：
// - StatusItemDropDetector：贴在 NSStatusItem button 上的透明覆盖层，注册 fileURL 拖拽。
//   拖入 → 弹出 DropPanel，拖离 → 延迟隐藏；鼠标事件原样转发给底下的 button，
//   保证点击打开菜单不受影响（spec 已知风险 4 的落点）
// - DropPanelController：无边框 nonactivating NSPanel，「机器 × 目录」平铺成行
// - DropRowView：单行独立 drop target，松手按文件引用模式上传（同路径 A）

@MainActor
final class DropPanelController {
    private let appState: AppState
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    private var clickMonitor: Any?
    private weak var statusButton: NSStatusBarButton?

    init(appState: AppState, statusButton: NSStatusBarButton?) {
        self.appState = appState
        self.statusButton = statusButton
        installDetector()
    }

    private func installDetector() {
        guard let button = statusButton else { return }
        let detector = StatusItemDropDetector(frame: button.bounds)
        detector.autoresizingMask = [.width, .height]
        detector.onDragEntered = { [weak self] in self?.show() }
        detector.onDragExited = { [weak self] in self?.scheduleHide() }
        button.addSubview(detector)
    }

    // MARK: - 显示/隐藏

    private func show() {
        cancelScheduledHide()
        guard panel == nil else { return }

        let rows: [DropTargetRow]
        if case .success(let config) = appState.configStore.lastResult {
            rows = DropTargets.rows(from: config)
        } else {
            rows = []
        }

        let panel = buildPanel(rows: rows)
        position(panel)
        panel.orderFrontRegardless()
        self.panel = panel

        // 面板不抢 key，点击别处不会自动关闭；全局鼠标按下即收起
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    private func hide() {
        cancelScheduledHide()
        panel?.orderOut(nil)
        panel = nil
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }

    /// 拖离图标/面板后延迟隐藏（拖回即取消），避免图标到面板途中的间隙闪没
    private func scheduleHide(after delay: TimeInterval = 0.7) {
        cancelScheduledHide()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelScheduledHide() {
        hideWork?.cancel()
        hideWork = nil
    }

    // MARK: - 面板构建

    private func buildPanel(rows: [DropTargetRow]) -> NSPanel {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let header = NSTextField(labelWithString: rows.isEmpty ? "配置中没有可用目录" : "拖到目标目录上传")
        header.font = .systemFont(ofSize: 11)
        header.textColor = .secondaryLabelColor
        stack.addArrangedSubview(header)
        stack.setCustomSpacing(6, after: header)

        for row in rows {
            let view = DropRowView(
                row: row,
                isEnabled: { [weak self] in self?.appState.isBusy == false },
                onDragActivity: { [weak self] entered in
                    entered ? self?.cancelScheduledHide() : self?.scheduleHide()
                },
                onDrop: { [weak self] urls, target in
                    self?.hide()
                    self?.appState.uploadDroppedFiles(urls, machine: target.machine, directory: target.directory)
                }
            )
            view.widthAnchor.constraint(equalToConstant: 264).isActive = true
            view.heightAnchor.constraint(equalToConstant: 32).isActive = true
            stack.addArrangedSubview(view)
        }

        let background = DropPanelBackgroundView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        background.onDragActivity = { [weak self] entered in
            entered ? self?.cancelScheduledHide() : self?.scheduleHide()
        }
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
        ])

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.contentView = background
        panel.setContentSize(background.fittingSize)
        return panel
    }

    /// 锚定在状态栏图标正下方，水平居中并夹取到屏幕可见范围内
    private func position(_ panel: NSPanel) {
        guard let buttonWindow = statusButton?.window, let screen = buttonWindow.screen ?? NSScreen.main else { return }
        let anchor = buttonWindow.frame
        let size = panel.frame.size
        var x = anchor.midX - size.width / 2
        x = min(max(x, screen.visibleFrame.minX + 4), screen.visibleFrame.maxX - size.width - 4)
        let y = anchor.minY - size.height - 6
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

// MARK: - 图标覆盖层

private final class StatusItemDropDetector: NSView {
    var onDragEntered: (() -> Void)?
    var onDragExited: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) else { return [] }
        onDragEntered?()
        return .generic
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragExited?()
    }

    // 图标本身不接收 drop，drop 只落在面板的目录行上
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { false }

    // 覆盖层挡在 button 上面，把鼠标事件原样转发回去，菜单点击行为不变
    override func mouseDown(with event: NSEvent) { superview?.mouseDown(with: event) }
    override func rightMouseDown(with event: NSEvent) { superview?.rightMouseDown(with: event) }
    override func otherMouseDown(with event: NSEvent) { superview?.otherMouseDown(with: event) }
}

// MARK: - 面板背景（非行区域的拖拽活动也要维持面板可见）

private final class DropPanelBackgroundView: NSVisualEffectView {
    var onDragActivity: ((_ entered: Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragActivity?(true)
        return .generic
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragActivity?(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { false }

    // 拖拽会话结束（drop 或取消）后的兜底收起
    override func draggingEnded(_ sender: NSDraggingInfo) {
        onDragActivity?(false)
    }
}

// MARK: - 目录行

private final class DropRowView: NSView {
    private let row: DropTargetRow
    private let isEnabled: () -> Bool
    private let onDragActivity: (_ entered: Bool) -> Void
    private let onDrop: (_ urls: [URL], _ target: DropTargetRow) -> Void
    private var highlighted = false {
        didSet { needsDisplay = true }
    }

    init(
        row: DropTargetRow,
        isEnabled: @escaping () -> Bool,
        onDragActivity: @escaping (_ entered: Bool) -> Void,
        onDrop: @escaping (_ urls: [URL], _ target: DropTargetRow) -> Void
    ) {
        self.row = row
        self.isEnabled = isEnabled
        self.onDragActivity = onDragActivity
        self.onDrop = onDrop
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        registerForDraggedTypes([.fileURL])

        let label = NSTextField(labelWithString: "📁 \(row.label)")
        label.font = .systemFont(ofSize: 13)
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard highlighted else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.3).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragActivity(true)
        guard isEnabled(), sender.draggingPasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) else { return [] }
        highlighted = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        highlighted = false
        onDragActivity(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        highlighted = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        highlighted = false
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty else { return false }
        onDrop(urls, row)
        return true
    }
}
