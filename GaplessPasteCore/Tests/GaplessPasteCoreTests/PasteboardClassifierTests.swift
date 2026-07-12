import Foundation
import Testing
@testable import GaplessPasteCore

@Suite("剪贴板分类：优先级 fileURLs > image > text")
struct PasteboardClassifierTests {
    let fileA = URL(fileURLWithPath: "/tmp/a.png")
    let fileB = URL(fileURLWithPath: "/tmp/b.txt")
    let png = Data([0x89, 0x50, 0x4E, 0x47])

    @Test("文件引用优先于图像与文本（Finder ⌘C 会同时带文件名文本）")
    func fileURLsWin() {
        let result = PasteboardClassifier.classify(fileURLs: [fileA, fileB], imagePNGData: png, text: "a.png")
        #expect(result == .fileReferences([fileA, fileB]))
    }

    @Test("无文件时图像优先于文本")
    func imageWinsOverText() {
        let result = PasteboardClassifier.classify(fileURLs: [], imagePNGData: png, text: "some text")
        #expect(result == .imageData(png))
    }

    @Test("仅文本")
    func textOnly() {
        let result = PasteboardClassifier.classify(fileURLs: [], imagePNGData: nil, text: "hello")
        #expect(result == .text("hello"))
    }

    @Test("全空 → empty")
    func allNilIsEmpty() {
        let result = PasteboardClassifier.classify(fileURLs: [], imagePNGData: nil, text: nil)
        #expect(result == .empty)
    }

    @Test("空字符串文本视为 empty")
    func emptyStringTextIsEmpty() {
        let result = PasteboardClassifier.classify(fileURLs: [], imagePNGData: nil, text: "")
        #expect(result == .empty)
    }

    @Test("零字节图像数据视为无图像")
    func emptyImageDataIgnored() {
        let result = PasteboardClassifier.classify(fileURLs: [], imagePNGData: Data(), text: "fallback")
        #expect(result == .text("fallback"))
    }

    @Test("图片文件判定：按扩展名（大小写不敏感），非图片/无扩展名为否")
    func imageFileURLDetection() {
        for name in ["a.png", "a.PNG", "a.jpg", "a.JPEG", "a.gif", "a.bmp", "a.tiff", "a.tif", "a.heic", "a.heif", "a.webp"] {
            #expect(PasteboardClassifier.isImageFileURL(URL(fileURLWithPath: "/tmp/\(name)")), "\(name) 应判定为图片")
        }
        for name in ["a.pdf", "a.txt", "a", "a.png.zip", "a.svg"] {
            #expect(!PasteboardClassifier.isImageFileURL(URL(fileURLWithPath: "/tmp/\(name)")), "\(name) 不应判定为图片")
        }
    }
}
