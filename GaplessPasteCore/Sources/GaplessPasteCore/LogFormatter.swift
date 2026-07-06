import Foundation

// 日志行的纯格式化逻辑。文件写入在 app 侧的 LogService。

public enum LogLevel: String, Sendable {
    case debug = "DEBUG"
    case info = "INFO"
    case error = "ERROR"
}

public enum LogFormatter {
    /// "2026-07-07 10:23:45.123 [INFO] message"；多行消息续行缩进 4 空格，
    /// 保证逐行 grep 时时间戳前缀可辨
    public static func line(date: Date, level: LogLevel, message: String, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let indented = message.replacingOccurrences(of: "\n", with: "\n    ")
        return "\(formatter.string(from: date)) [\(level.rawValue)] \(indented)"
    }

    /// argv → 可读命令行：含空格/引号的参数用单引号包裹，其余原样
    public static func describeCommand(_ argv: [String]) -> String {
        argv.map { arg in
            if arg.isEmpty || arg.contains(where: { $0 == " " || $0 == "'" || $0 == "\"" }) {
                return SSHCommandBuilder.shellQuote(arg)
            }
            return arg
        }.joined(separator: " ")
    }
}
