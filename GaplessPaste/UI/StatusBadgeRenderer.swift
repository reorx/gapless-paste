import AppKit
import GaplessPasteCore

enum StatusBadgeRenderer {
    static func image(feedback: TransferPresentation.Feedback, badgeAlpha: CGFloat = 1) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let base = NSImage(systemSymbolName: "arrow.up.doc.on.clipboard", accessibilityDescription: nil)!
            // 主图标的位置与尺寸在所有状态固定；右下角留出独立徽标空间。
            base.draw(in: NSRect(x: 0, y: 3, width: 13, height: 15))
            if let name = feedback.symbolName {
                let badge = NSImage(systemSymbolName: name, accessibilityDescription: nil)!
                    .withSymbolConfiguration(.init(pointSize: 9, weight: .bold))!
                badge.draw(in: NSRect(x: 11, y: 0, width: 7, height: 9), from: .zero, operation: .sourceOver, fraction: badgeAlpha)
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
