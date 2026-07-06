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
}
