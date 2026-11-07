import AppKit
import SwiftUI
import GaplessPasteCore

/// 设置和各个文本预览共享同一个本机偏好，不参与机器配置的保存。
enum PreviewPreferences {
    static let textFontSizeKey = "previewTextFontSize"
}

struct PreviewTextPreferences: View {
    @AppStorage(PreviewPreferences.textFontSizeKey) private var storedFontSize = PreviewTextFontSize.defaultValue

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("文本预览")
                    .font(.callout.weight(.medium))
                Text("只调整文本正文，立即应用到所有预览窗口")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Stepper(value: Binding(
                get: { PreviewTextFontSize.normalize(storedFontSize) },
                set: { storedFontSize = PreviewTextFontSize.normalize($0) }
            ), in: PreviewTextFontSize.range, step: PreviewTextFontSize.step) {
                Text("字号 \(PreviewTextFontSize.normalize(storedFontSize).formatted()) pt")
                    .monospacedDigit()
            }
            .fixedSize()
            .accessibilityLabel("文本预览字号")
            .accessibilityIdentifier("settings-preview-font-size")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

/// 把偏好订阅留在正文，字号变化不重建文件预览或播放器。
struct PreviewTextBody: View {
    let text: String
    @AppStorage(PreviewPreferences.textFontSizeKey) private var storedFontSize = PreviewTextFontSize.defaultValue

    var body: some View {
        SelectablePreviewText(text: text, fontSize: PreviewTextFontSize.normalize(storedFontSize))
    }
}

/// SwiftUI Text 会一次布局整段长文本，大字号下可阻塞主线程数分钟。
/// 原生文本视图按需布局可见区域，同时保留字号变化时的文本选区和滚动容器。
private struct SelectablePreviewText: NSViewRepresentable {
    let text: String
    let fontSize: Double

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        let textView = scrollView.documentView as! NSTextView
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textContainer?.lineFragmentPadding = 0
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.setAccessibilityIdentifier("preview-text-body")
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        if textView.font != font {
            textView.font = font
        }
    }
}
