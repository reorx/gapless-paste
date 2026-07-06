import AppKit

// 图像上传前的重命名浮窗：居中偏上 NSPanel，可成 key window。
// 输入框只持有主文件名（扩展名 .png 以尾标签锁定），预填后整体选中，
// Enter = 确认上传（默认按钮），Esc = 取消。
// 弹出时临时抢焦点，关闭后 NSApp.hide 把焦点交还前台 app。

@MainActor
final class RenamePopup: NSObject, NSTextFieldDelegate {
    private var panel: NSPanel?
    private var stemField: NSTextField?
    private var continuation: CheckedContinuation<String?, Never>?

    /// 返回用户确认的主文件名（不含扩展名）；nil = 取消
    func requestImageStem(defaultStem: String, image: NSImage, targetLabel: String) async -> String? {
        guard continuation == nil else { return nil }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            present(defaultStem: defaultStem, image: image, targetLabel: targetLabel)
        }
    }

    private func present(defaultStem: String, image: NSImage, targetLabel: String) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 280),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.title = "上传到 \(targetLabel)"
        panel.level = .floating
        panel.isReleasedWhenClosed = false

        let imageView = NSImageView()
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.widthAnchor.constraint(lessThanOrEqualToConstant: 320).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: 160).isActive = true

        let field = NSTextField(string: defaultStem)
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        stemField = field

        let extLabel = NSTextField(labelWithString: ".png")
        extLabel.textColor = .secondaryLabelColor

        let nameRow = NSStackView(views: [field, extLabel])
        nameRow.orientation = .horizontal
        nameRow.spacing = 4

        let cancelButton = NSButton(title: "取消", target: self, action: #selector(cancelTapped))
        cancelButton.keyEquivalent = "\u{1b}"
        let confirmButton = NSButton(title: "上传", target: self, action: #selector(confirmTapped))
        confirmButton.keyEquivalent = "\r"

        let buttonRow = NSStackView(views: [cancelButton, confirmButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        let stack = NSStackView(views: [imageView, nameRow, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        panel.contentView = stack

        // 居中偏上
        panel.layoutIfNeeded()
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.minY + frame.height * 0.72 - size.height / 2
            ))
        }

        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field) // 成为第一响应者时默认全选，正好实现「选中主文件名」

    }

    @objc private func confirmTapped() {
        let stem = stemField?.stringValue.trimmingCharacters(in: .whitespaces) ?? ""
        finish(with: stem.isEmpty ? nil : stem)
    }

    @objc private func cancelTapped() {
        finish(with: nil)
    }

    // 输入框编辑中按 Esc 走 cancelOperation（Enter 由默认按钮的 keyEquivalent 接管）
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            finish(with: nil)
            return true
        }
        return false
    }

    private func finish(with stem: String?) {
        panel?.orderOut(nil)
        panel = nil
        stemField = nil
        NSApp.hide(nil) // 交还焦点给之前的前台 app
        continuation?.resume(returning: stem)
        continuation = nil
    }
}
