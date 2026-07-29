import Foundation
import Testing
@testable import GaplessPasteCore

@Suite("远端剪贴板注入：平台探测结果 → 注入命令（M2）")
struct RemoteClipboardTests {
    let darwin = ProbeResult(home: "/Users/reorx", unameString: "Darwin")
    let linux = ProbeResult(home: "/home/reorx", unameString: "Linux")

    // 已在真实 mini 上验证过的命令形态（2026-07-07）：
    // osascript -e 'set the clipboard to (read (POSIX file "<path>") as «class PNGf»)'
    @Test("Darwin 图像注入：osascript + POSIX file + «class PNGf»")
    func darwinImageInjection() {
        let command = RemoteClipboard.imageInjectionCommand(
            probe: darwin,
            remoteImagePath: "/Users/reorx/claude-inbox/shot.png"
        )
        #expect(command == #"osascript -e 'set the clipboard to (read (POSIX file "/Users/reorx/claude-inbox/shot.png") as «class PNGf»)'"#)
    }

    @Test("图像注入路径的两层转义：AppleScript 双引号层 + shell 单引号层")
    func imageInjectionEscaping() {
        // 路径含双引号与反斜杠：AppleScript 字符串层需转义
        let withQuote = RemoteClipboard.imageInjectionCommand(probe: darwin, remoteImagePath: #"/a/b"c\d.png"#)
        #expect(withQuote == #"osascript -e 'set the clipboard to (read (POSIX file "/a/b\"c\\d.png") as «class PNGf»)'"#)

        // 路径含单引号：shell 单引号层需 '\'' 转义
        let withSingleQuote = RemoteClipboard.imageInjectionCommand(probe: darwin, remoteImagePath: "/a/it's.png")
        #expect(withSingleQuote == "osascript -e 'set the clipboard to (read (POSIX file \"/a/it'\\''s.png\") as «class PNGf»)'")
    }

    @Test("非 Darwin 图像注入返回 nil（降级路径模式）")
    func nonDarwinImageInjectionIsNil() {
        #expect(RemoteClipboard.imageInjectionCommand(probe: linux, remoteImagePath: "/tmp/a.png") == nil)
    }

    @Test("Darwin 文本注入：pbcopy（文本经 stdin 传输，不进 argv）")
    func darwinTextInjection() {
        #expect(RemoteClipboard.textInjectionCommand(probe: darwin) == "pbcopy")
    }

    @Test("非 Darwin 文本注入返回 nil")
    func nonDarwinTextInjectionIsNil() {
        #expect(RemoteClipboard.textInjectionCommand(probe: linux) == nil)
    }

    @Test("同步路径的固定远端临时文件：~/.cache/gapless-paste/clipboard.png，每次覆盖")
    func syncTemporaryPath() {
        #expect(RemoteClipboard.syncTemporaryDirectory(probe: darwin) == "/Users/reorx/.cache/gapless-paste")
        #expect(RemoteClipboard.syncTemporaryPath(probe: darwin) == "/Users/reorx/.cache/gapless-paste/clipboard.png")
    }

    // MARK: - 反向：从远端剪贴板拉取（远端 → 本机）

    @Test("Darwin 图像提取：osascript try «class PNGf»，非图像时输出哨兵")
    func darwinImageExtraction() {
        let command = RemoteClipboard.imageExtractionCommand(probe: darwin)
        let script = """
        try
        the clipboard as «class PNGf»
        on error
        "\(RemoteClipboard.notImageSentinel)"
        end try
        """
        #expect(command == "osascript -e '\(script)'")
    }

    @Test("非 Darwin 图像提取返回 nil（不支持拉取）")
    func nonDarwinImageExtractionIsNil() {
        #expect(RemoteClipboard.imageExtractionCommand(probe: linux) == nil)
    }

    @Test("Darwin 文本提取：pbpaste（内容经 stdout 回传）")
    func darwinTextExtraction() {
        #expect(RemoteClipboard.textExtractionCommand(probe: darwin) == "pbpaste")
    }

    @Test("非 Darwin 文本提取返回 nil")
    func nonDarwinTextExtractionIsNil() {
        #expect(RemoteClipboard.textExtractionCommand(probe: linux) == nil)
    }

    @Test("提取输出解析：«data PNGf<hex>» → PNG 字节")
    func parseImageOutput() {
        // PNG 魔数 89 50 4E 47
        let output = "«data PNGf89504E47»\n"
        #expect(
            RemoteClipboard.parseImageExtractionOutput(output)
                == .imagePNG(Data([0x89, 0x50, 0x4E, 0x47]))
        )
    }

    @Test("提取输出解析：小写 hex 同样接受")
    func parseImageOutputLowercaseHex() {
        #expect(
            RemoteClipboard.parseImageExtractionOutput("«data PNGf89504e47»")
                == .imagePNG(Data([0x89, 0x50, 0x4E, 0x47]))
        )
    }

    @Test("提取输出解析：哨兵字符串 → notImage（上层转走 pbpaste 文本路径）")
    func parseNotImageOutput() {
        #expect(
            RemoteClipboard.parseImageExtractionOutput("\(RemoteClipboard.notImageSentinel)\n")
                == .notImage
        )
    }

    @Test("提取输出解析：奇数长度 hex / 非法字符 / 其他输出 → unrecognized")
    func parseUnrecognizedOutput() {
        #expect(RemoteClipboard.parseImageExtractionOutput("«data PNGf895»") == .unrecognized)
        #expect(RemoteClipboard.parseImageExtractionOutput("«data PNGfZZ»") == .unrecognized)
        #expect(RemoteClipboard.parseImageExtractionOutput("random garbage") == .unrecognized)
        #expect(RemoteClipboard.parseImageExtractionOutput("") == .unrecognized)
    }
}
