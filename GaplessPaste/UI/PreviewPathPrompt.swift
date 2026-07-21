import AppKit
import GaplessPasteCore

/// 预览远端目录的路径输入弹窗：文本框 + 近期路径快捷填充（点击覆盖输入框）。
/// 返回 trim 后的非空路径；取消或空输入返回 nil
@MainActor
enum PreviewPathPrompt {
    static func run(machineName: String, recentPaths: [String]) -> String? {
        let alert = NSAlert()
        alert.messageText = "预览远端目录"
        alert.informativeText = "输入 \(machineName) 上的目录路径（支持 ~/ 前缀）"

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = "~/"
        field.placeholderString = "~/claude-inbox"
        field.setAccessibilityIdentifier("preview-path-field")

        let filler = FieldFiller(field: field)
        alert.accessoryView = makeAccessory(field: field, recentPaths: recentPaths, filler: filler)
        alert.addButton(withTitle: "打开预览")
        alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        _ = filler // 按钮 target 是弱引用，保活到 runModal 结束
        let path = field.stringValue.trimmingCharacters(in: .whitespaces)
        return path.isEmpty ? nil : path
    }

    private static func makeAccessory(field: NSTextField, recentPaths: [String], filler: FieldFiller) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.addArrangedSubview(field)
        field.widthAnchor.constraint(equalToConstant: 280).isActive = true

        if !recentPaths.isEmpty {
            let label = NSTextField(labelWithString: "近期路径：")
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            label.textColor = .secondaryLabelColor
            stack.addArrangedSubview(label)
            for (index, path) in recentPaths.enumerated() {
                let button = NSButton(title: path, target: filler, action: #selector(FieldFiller.fill(_:)))
                button.isBordered = false
                button.contentTintColor = .linkColor
                button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
                button.lineBreakMode = .byTruncatingMiddle
                button.setAccessibilityIdentifier("preview-recent-\(index)")
                stack.addArrangedSubview(button)
                button.widthAnchor.constraint(lessThanOrEqualToConstant: 280).isActive = true
            }
        }

        stack.frame = NSRect(x: 0, y: 0, width: 280, height: stack.fittingSize.height)
        return stack
    }
}

/// 近期路径按钮的点击目标：把按钮标题覆盖进输入框并聚焦
private final class FieldFiller: NSObject {
    private weak var field: NSTextField?

    init(field: NSTextField) {
        self.field = field
    }

    @objc func fill(_ sender: NSButton) {
        field?.stringValue = sender.title
        if let field {
            field.window?.makeFirstResponder(field)
            field.currentEditor()?.moveToEndOfLine(nil)
        }
    }
}
