import Foundation

// 首次对某机器操作时执行一次探测（结果缓存，重载配置时清缓存）：
//   ssh <host> 'echo "$HOME"; uname'
// $HOME 用于把配置里 ~/ 目录展开为绝对路径（M1 路径回传依赖）；
// uname 用于远端平台判定（M2 剪贴板注入消费），一次拿全避免两次往返

public struct ProbeResult: Equatable, Codable, Sendable {
    public let home: String
    public let unameString: String

    public init(home: String, unameString: String) {
        self.home = home
        self.unameString = unameString
    }

    public var isDarwin: Bool { unameString == "Darwin" }

    /// 探测用的远端命令（经 ssh 执行）
    public static let shellCommand = #"echo "$HOME"; uname"#

    /// 解析探测输出：前两个非空行 = $HOME、uname；home 必须是绝对路径
    public static func parse(_ output: String) -> ProbeResult? {
        let lines = output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard lines.count >= 2, lines[0].hasPrefix("/") else { return nil }
        return ProbeResult(home: lines[0], unameString: lines[1])
    }

    /// 把配置里的 ~/ 前缀展开为绝对路径；绝对路径原样返回
    public func expandPath(_ path: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + path.dropFirst(1) }
        return path
    }
}
