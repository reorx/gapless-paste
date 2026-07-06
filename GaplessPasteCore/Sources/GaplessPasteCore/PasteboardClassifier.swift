import Foundation

// 剪贴板快照分类。app 侧负责读 NSPasteboard 并把 TIFF 转成 PNG，
// 这里只做纯逻辑判定，优先级：fileURLs > image > text
// （Finder ⌘C 文件时剪贴板会同时带文件名文本，故文件引用必须最高优先）

public enum ClassifiedContent: Equatable, Sendable {
    case fileReferences([URL])
    case imageData(Data)
    case text(String)
    case empty
}

public enum PasteboardClassifier {
    public static func classify(fileURLs: [URL], imagePNGData: Data?, text: String?) -> ClassifiedContent {
        if !fileURLs.isEmpty {
            return .fileReferences(fileURLs)
        }
        if let imagePNGData, !imagePNGData.isEmpty {
            return .imageData(imagePNGData)
        }
        if let text, !text.isEmpty {
            return .text(text)
        }
        return .empty
    }
}
