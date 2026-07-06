import AppKit
import GaplessPasteCore

// 文件日志：~/Library/Logs/GaplessPaste/GaplessPaste.log
// 固定路径，命令行可直接 tail/cat（Console.app 也会索引 ~/Library/Logs）。
// 写入走串行队列，SSHRunner 的后台线程与主线程都可安全调用。

final class LogService: @unchecked Sendable {
    static let logFileURL = FileManager.default
        .urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/GaplessPaste/GaplessPaste.log")

    private static let rotateBytes: UInt64 = 5_000_000

    private let queue = DispatchQueue(label: "com.reorx.gaplesspaste.log")
    private var handle: FileHandle?

    init() {
        let url = Self.logFileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        rotateIfNeeded(url)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: url)
        _ = try? handle?.seekToEnd()
    }

    /// 超过 5MB 时滚动为 .log.1（覆盖旧的），避免无限膨胀
    private func rotateIfNeeded(_ url: URL) {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? UInt64,
              size > Self.rotateBytes
        else { return }
        let backup = url.deletingPathExtension().appendingPathExtension("log.1")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: url, to: backup)
    }

    func log(_ level: LogLevel, _ message: String) {
        let line = LogFormatter.line(date: Date(), level: level, message: message) + "\n"
        queue.async { [handle] in
            if let data = line.data(using: .utf8) {
                try? handle?.write(contentsOf: data)
            }
        }
    }

    func debug(_ message: String) { log(.debug, message) }
    func info(_ message: String) { log(.info, message) }
    func error(_ message: String) { log(.error, message) }

    @MainActor
    func openInViewer() {
        NSWorkspace.shared.open(Self.logFileURL)
    }
}
