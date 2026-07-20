import Foundation
import Testing
@testable import GaplessPasteCore

// 预览远端目录：目录列表解析、路径拼接、预览类型判定、文本预览解码

struct RemoteBrowseTests {
    // MARK: - 列表解析（ls -1Ap 输出：目录带尾随 /）

    @Test func parseListingSplitsDirectoriesAndFiles() {
        let output = """
        notes.md
        src/
        README
        """
        let entries = RemoteBrowse.parseListing(output)
        #expect(entries == [
            RemoteEntry(name: "src", isDirectory: true),
            RemoteEntry(name: "notes.md", isDirectory: false),
            RemoteEntry(name: "README", isDirectory: false),
        ])
    }

    @Test func parseListingSortsDirectoriesFirstThenCaseInsensitive() {
        let output = """
        zeta.txt
        Alpha.txt
        beta/
        .config/
        .hidden
        """
        let entries = RemoteBrowse.parseListing(output)
        #expect(entries.map(\.name) == [".config", "beta", ".hidden", "Alpha.txt", "zeta.txt"])
        #expect(entries.map(\.isDirectory) == [true, true, false, false, false])
    }

    @Test func parseListingEmptyOutputMeansEmptyDirectory() {
        #expect(RemoteBrowse.parseListing("") == [])
        #expect(RemoteBrowse.parseListing("\n\n") == [])
    }

    // MARK: - 路径拼接

    @Test func joinPathHandlesTrailingSlashAndRoot() {
        #expect(RemoteBrowse.joinPath("/home/me", "src") == "/home/me/src")
        #expect(RemoteBrowse.joinPath("/home/me/", "src") == "/home/me/src")
        #expect(RemoteBrowse.joinPath("/", "etc") == "/etc")
    }

    // MARK: - 预览类型判定（扩展名，大小写不敏感）

    @Test func previewKindImageByExtension() {
        #expect(FilePreview.kind(forFileName: "shot.png") == .image)
        #expect(FilePreview.kind(forFileName: "PHOTO.JPG") == .image)
        #expect(FilePreview.kind(forFileName: "pic.heic") == .image)
    }

    @Test func previewKindDefaultsToText() {
        #expect(FilePreview.kind(forFileName: "notes.md") == .text)
        #expect(FilePreview.kind(forFileName: "Makefile") == .text)
        #expect(FilePreview.kind(forFileName: "image.svg") == .text) // SVG 是 XML，按文本预览
    }

    // MARK: - 文本预览解码（UTF-8 + 截断；二进制返回 nil）

    @Test func decodeTextValidUTF8() {
        let result = FilePreview.decodeText(Data("hello 世界".utf8))
        #expect(result?.text == "hello 世界")
        #expect(result?.truncated == false)
    }

    @Test func decodeTextRejectsBinary() {
        let binary = Data([0x00, 0xFF, 0xFE, 0x00, 0x89, 0x50])
        #expect(FilePreview.decodeText(binary) == nil)
    }

    @Test func decodeTextTruncatesOverLimit() {
        let data = Data(String(repeating: "a", count: 100).utf8)
        let result = FilePreview.decodeText(data, limit: 10)
        #expect(result?.text == String(repeating: "a", count: 10))
        #expect(result?.truncated == true)
    }

    @Test func decodeTextTruncationDoesNotBreakMultibyteCharacter() {
        // "世" 是 3 字节，limit=4 会切在第二个字符中间，应回退到完整字符边界
        let data = Data("世界".utf8)
        let result = FilePreview.decodeText(data, limit: 4)
        #expect(result?.text == "世")
        #expect(result?.truncated == true)
    }
}

struct SSHCommandBuilderBrowseTests {
    let builder = SSHCommandBuilder(controlPathDirectory: "/tmp/gp-sockets")

    @Test func listDirectoryCommandQuotesPath() {
        let argv = builder.listDirectoryCommand(host: "mini", remotePath: "/home/me/my dir")
        #expect(argv.first == "/usr/bin/ssh")
        #expect(argv.last == "LC_ALL=C ls -1Ap -- '/home/me/my dir'")
        #expect(argv.contains("mini"))
    }

    @Test func scpDownloadCommandBuildsRemoteToLocal() {
        let argv = builder.scpDownloadCommand(host: "mini", remotePath: "/home/me/a.txt", localPath: "/tmp/cache/a.txt")
        #expect(argv.first == "/usr/bin/scp")
        #expect(argv.suffix(2) == ["mini:/home/me/a.txt", "/tmp/cache/a.txt"])
    }
}
