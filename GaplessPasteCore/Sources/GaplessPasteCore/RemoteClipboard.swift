import Foundation

// 平台探测结果 → 远端剪贴板注入命令（经 ssh 执行的远端命令字符串）。
// Darwin: osascript «class PNGf» / pbcopy；非 Darwin: nil → 上层降级
// （目录上传降级为路径模式，「同步剪贴板」菜单项禁用）。
// 命令形态已在真实 Mac mini 上验证（2026-07-07）：SSH 用户与已登录
// GUI 会话用户一致时，osascript 写剪贴板生效。

public enum RemoteClipboard {
    /// 图像注入：远端已有 PNG 文件（目录上传产物或同步临时文件）→ 读入远端剪贴板。
    /// 两层转义：路径先按 AppleScript 双引号字符串转义，整段脚本再按 shell 单引号转义
    public static func imageInjectionCommand(probe: ProbeResult, remoteImagePath: String) -> String? {
        guard probe.isDarwin else { return nil }
        let script = #"set the clipboard to (read (POSIX file "\#(appleScriptStringEscape(remoteImagePath))") as «class PNGf»)"#
        return "osascript -e \(SSHCommandBuilder.shellQuote(script))"
    }

    /// 文本注入：pbcopy，文本本体经 stdin 传输（不进 argv，避免长度与转义问题）
    public static func textInjectionCommand(probe: ProbeResult) -> String? {
        guard probe.isDarwin else { return nil }
        return "pbcopy"
    }

    /// 「同步剪贴板」图像的固定远端临时路径，每次覆盖不累积
    public static func syncTemporaryDirectory(probe: ProbeResult) -> String {
        probe.expandPath("~/.cache/gapless-paste")
    }

    public static func syncTemporaryPath(probe: ProbeResult) -> String {
        syncTemporaryDirectory(probe: probe) + "/clipboard.png"
    }

    /// AppleScript 双引号字符串字面量转义：\ → \\，" → \"
    static func appleScriptStringEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: #"\"#, with: #"\\"#)
            .replacingOccurrences(of: #"""#, with: #"\""#)
    }

    // MARK: - 反向：从远端剪贴板拉取（远端 → 本机）

    /// 图像提取命令的输出解析结果
    public enum ExtractionOutput: Equatable, Sendable {
        case imagePNG(Data)
        /// 远端剪贴板不是图像（哨兵命中），上层改走 pbpaste 文本路径
        case notImage
        case unrecognized
    }

    /// osascript 对非图像剪贴板 coerce «class PNGf» 会报错，try 分支输出此哨兵区分
    public static let notImageSentinel = "GAPLESSPASTE_NOT_IMAGE"

    /// 图像提取：远端剪贴板若为图像，osascript 把结果按 «data PNGf<hex>» 打印到
    /// stdout（一次 ssh 往返拿到完整图像，hex 在本机解码）；非图像则输出哨兵。
    /// 非 Darwin 返回 nil（拉取不支持）
    public static func imageExtractionCommand(probe: ProbeResult) -> String? {
        guard probe.isDarwin else { return nil }
        let script = """
        try
        the clipboard as «class PNGf»
        on error
        "\(notImageSentinel)"
        end try
        """
        return "osascript -e \(SSHCommandBuilder.shellQuote(script))"
    }

    /// 文本提取：pbpaste，内容经 stdout 回传（空剪贴板输出为空，由上层判定）
    public static func textExtractionCommand(probe: ProbeResult) -> String? {
        guard probe.isDarwin else { return nil }
        return "pbpaste"
    }

    /// 解析图像提取命令的 stdout：«data PNGf<hex>» → PNG 字节；哨兵 → notImage
    public static func parseImageExtractionOutput(_ stdout: String) -> ExtractionOutput {
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == notImageSentinel { return .notImage }
        guard trimmed.hasPrefix("«data PNGf"), trimmed.hasSuffix("»") else { return .unrecognized }
        let hex = trimmed.dropFirst("«data PNGf".count).dropLast(1)
        guard let data = hexDecode(hex) else { return .unrecognized }
        return .imagePNG(data)
    }

    /// hex 字符串 → 字节；奇数长度或非法字符返回 nil
    static func hexDecode(_ hex: Substring) -> Data? {
        guard hex.count.isMultiple(of: 2), !hex.isEmpty else { return nil }
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }
}
