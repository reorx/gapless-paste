import AppKit

// NSPasteboard 读写。读出的原始快照交给 Core 的 PasteboardClassifier 分类；
// 图像统一转成 PNG 数据（部分应用只放 TIFF，见 spec 已知风险 3）

@MainActor
final class PasteboardService {
    struct Snapshot {
        let fileURLs: [URL]
        let imagePNGData: Data?
        let text: String?
    }

    func snapshot() -> Snapshot {
        let pasteboard = NSPasteboard.general
        let urls = (pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]) ?? []
        return Snapshot(
            fileURLs: urls,
            imagePNGData: readPNG(from: pasteboard),
            text: pasteboard.string(forType: .string)
        )
    }

    private func readPNG(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) {
            return png
        }
        if let tiff = pasteboard.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return png
        }
        return nil
    }

    func writeText(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}
