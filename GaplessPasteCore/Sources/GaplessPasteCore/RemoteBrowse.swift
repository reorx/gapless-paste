import Foundation

// 预览远端目录（Preview folder）的纯逻辑：
// 目录列表命令输出解析、路径拼接、文件预览类型判定与文本解码。
// 列目录用 POSIX 通用的 `ls -1Ap`：-1 一行一项、-A 含点文件（不含 . ..）、
// -p 目录追加尾随 /。注：符号链接不追加 /（会被当作文件），v1 接受此局限。

public struct RemoteEntry: Equatable, Sendable {
    public let name: String
    public let isDirectory: Bool

    public init(name: String, isDirectory: Bool) {
        self.name = name
        self.isDirectory = isDirectory
    }
}

public enum RemoteBrowse {
    /// 列目录的远端命令（经 ssh 执行）。LC_ALL=C 固定输出行为
    public static func listCommand(path: String) -> String {
        "LC_ALL=C ls -1Ap -- \(SSHCommandBuilder.shellQuote(path))"
    }

    /// 解析 ls -1Ap 输出：尾随 / 为目录。目录在前，各组内按名称大小写不敏感排序
    public static func parseListing(_ output: String) -> [RemoteEntry] {
        let entries = output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { line -> RemoteEntry in
                if line.hasSuffix("/") {
                    return RemoteEntry(name: String(line.dropLast()), isDirectory: true)
                }
                return RemoteEntry(name: String(line), isDirectory: false)
            }
        return entries.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    public static func joinPath(_ directory: String, _ name: String) -> String {
        if directory.hasSuffix("/") {
            return directory + name
        }
        return directory + "/" + name
    }

    /// 目录路径规范化：折叠连续 /、去掉尾随 /（根 / 保持不变）。
    /// 树节点 id 以此为准，保证输入路径与父目录列表拼出的子路径一致（导航复用节点）
    public static func normalizedDirectoryPath(_ path: String) -> String {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        let joined = components.joined(separator: "/")
        guard path.hasPrefix("/") else { return joined }
        return "/" + joined
    }

    /// 上一级目录；根 / 与相对路径返回 nil（无法向上）
    public static func parentPath(_ path: String) -> String? {
        let normalized = normalizedDirectoryPath(path)
        guard normalized.hasPrefix("/"), normalized != "/" else { return nil }
        let parent = (normalized as NSString).deletingLastPathComponent
        return parent.isEmpty ? "/" : parent
    }

    /// path 是否位于 directory 之下（不含 directory 自身；按路径段判断，/ab 不在 /a 之下）
    public static func isPath(_ path: String, inside directory: String) -> Bool {
        let base = normalizedDirectoryPath(directory)
        let prefix = base == "/" ? "/" : base + "/"
        return path.hasPrefix(prefix) && path.count > prefix.count
    }
}

public enum PreviewKind: Equatable, Sendable {
    case image
    case audio
    case text
}

public enum FilePreview {
    /// 文本预览上限：超出只取前缀展示（避免大文件撑爆内存/UI）
    public static let maxTextPreviewBytes = 512 * 1024

    /// 可在预览窗口内播放的音频扩展名（AVAudioPlayer 可解码的常见格式；ogg/opus 不支持）
    public static let audioFileExtensions: Set<String> = [
        "wav", "mp3", "m4a", "aac", "flac", "aiff", "aif", "caf",
    ]

    /// 按扩展名判定预览类型：已知图像格式走图像渲染，已知音频格式走播放器，
    /// 其余一律按文本尝试（SVG 是 XML 按文本；真二进制由 decodeText 的 UTF-8 校验兜底拒绝）
    public static func kind(forFileName name: String) -> PreviewKind {
        let ext = (name as NSString).pathExtension.lowercased()
        if PasteboardClassifier.imageFileExtensions.contains(ext) { return .image }
        if audioFileExtensions.contains(ext) { return .audio }
        return .text
    }

    /// 解码文本预览：超限截断到 limit 字节（回退到完整 UTF-8 字符边界），
    /// 非 UTF-8 数据返回 nil（视为二进制，不可预览）
    public static func decodeText(_ data: Data, limit: Int = maxTextPreviewBytes) -> (text: String, truncated: Bool)? {
        let truncated = data.count > limit
        var slice = truncated ? data.prefix(limit) : data
        if truncated {
            // 截断可能切在多字节字符中间，最多回退 3 字节找到合法边界
            for _ in 0..<3 {
                if String(data: slice, encoding: .utf8) != nil { break }
                slice = slice.dropLast()
            }
        }
        guard let text = String(data: slice, encoding: .utf8) else { return nil }
        return (text, truncated)
    }
}

extension SSHCommandBuilder {
    public func listDirectoryCommand(host: String, remotePath: String) -> [String] {
        sshCommand(host: host, remoteCommand: RemoteBrowse.listCommand(path: remotePath))
    }

    /// 远端 → 本地下载（预览缓存用）。与上传同理走 SFTP，远端路径原样单参数传递
    public func scpDownloadCommand(host: String, remotePath: String, localPath: String) -> [String] {
        ["/usr/bin/scp"] + baseOptions + ["\(host):\(remotePath)", localPath]
    }
}
