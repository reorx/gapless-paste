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
    /// 可按图像同步到远端剪贴板的文件扩展名（ImageIO 可解码、能转成 PNG 的常见格式）
    public static let imageFileExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "heic", "heif", "webp",
    ]

    /// 按扩展名（大小写不敏感）判定文件引用是否为图片文件
    public static func isImageFileURL(_ url: URL) -> Bool {
        imageFileExtensions.contains(url.pathExtension.lowercased())
    }

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
