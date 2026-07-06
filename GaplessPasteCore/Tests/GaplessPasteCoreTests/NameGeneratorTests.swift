import Foundation
import Testing
@testable import GaplessPasteCore

@Suite("命名：默认名、清洗、重名后缀")
struct NameGeneratorTests {
    @Test("默认图像名 shot-YYYYMMDD-HHmmss.png")
    func defaultImageName() {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 6
        components.hour = 15
        components.minute = 30
        components.second = 12
        components.timeZone = TimeZone(identifier: "UTC")
        let date = Calendar(identifier: .gregorian).date(from: components)!
        let name = NameGenerator.defaultImageName(for: date, timeZone: TimeZone(identifier: "UTC")!)
        #expect(name == "shot-20260706-153012.png")
    }

    @Test("清洗：/、:、空白、控制字符替换为 -")
    func sanitizeReplacesUnsafeChars() {
        #expect(NameGenerator.sanitize("a/b:c d\te\nf") == "a-b-c-d-e-f")
        #expect(NameGenerator.sanitize("Screen Shot 2026") == "Screen-Shot-2026")
        #expect(NameGenerator.sanitize("normal-name.png") == "normal-name.png")
    }

    @Test("清洗后为空 → 回落 untitled")
    func sanitizeEmptyFallsBack() {
        #expect(NameGenerator.sanitize("") == "untitled")
        #expect(NameGenerator.sanitize("   ") == "untitled")
    }

    @Test("重名后缀插入在扩展名之前")
    func suffixBeforeExtension() {
        #expect(NameGenerator.appendingSuffix("shot.png", index: 1) == "shot-1.png")
        #expect(NameGenerator.appendingSuffix("shot.png", index: 12) == "shot-12.png")
        #expect(NameGenerator.appendingSuffix("archive.tar.gz", index: 1) == "archive.tar-1.gz")
    }

    @Test("无扩展名直接追加")
    func suffixWithoutExtension() {
        #expect(NameGenerator.appendingSuffix("README", index: 2) == "README-2")
    }

    @Test("点开头的隐藏文件视为无扩展名")
    func suffixDotfile() {
        #expect(NameGenerator.appendingSuffix(".gitignore", index: 1) == ".gitignore-1")
    }

    @Test("firstAvailable：无冲突返回原名，有冲突递增到可用")
    func firstAvailable() {
        let taken: Set<String> = ["shot.png", "shot-1.png", "shot-2.png"]
        #expect(NameGenerator.firstAvailable("free.png") { taken.contains($0) } == "free.png")
        #expect(NameGenerator.firstAvailable("shot.png") { taken.contains($0) } == "shot-3.png")
    }
}
