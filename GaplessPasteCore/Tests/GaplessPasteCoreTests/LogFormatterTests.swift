import Foundation
import Testing
@testable import GaplessPasteCore

@Suite("日志格式化：时间戳、级别、多行缩进、命令描述")
struct LogFormatterTests {
    private func makeDate(nanosecond: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 7
        components.hour = 10
        components.minute = 23
        components.second = 45
        components.nanosecond = nanosecond
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    @Test("单行：时间戳（含毫秒）+ 级别 + 消息")
    func singleLine() {
        let line = LogFormatter.line(
            date: makeDate(),
            level: .info,
            message: "hello",
            timeZone: TimeZone(identifier: "UTC")!
        )
        #expect(line == "2026-07-07 10:23:45.000 [INFO] hello")
    }

    @Test("毫秒部分来自 Date")
    func milliseconds() {
        let line = LogFormatter.line(
            date: makeDate(nanosecond: 500_000_000),
            level: .error,
            message: "boom",
            timeZone: TimeZone(identifier: "UTC")!
        )
        #expect(line == "2026-07-07 10:23:45.500 [ERROR] boom")
    }

    @Test("多行消息续行缩进，保证逐行 grep 时前缀可辨")
    func multilineIndented() {
        let line = LogFormatter.line(
            date: makeDate(),
            level: .error,
            message: "scp failed\nstderr line 1\nstderr line 2",
            timeZone: TimeZone(identifier: "UTC")!
        )
        #expect(line == "2026-07-07 10:23:45.000 [ERROR] scp failed\n    stderr line 1\n    stderr line 2")
    }

    @Test("命令描述：含空格的参数加引号，普通参数原样")
    func describeCommand() {
        let description = LogFormatter.describeCommand(["/usr/bin/scp", "/tmp/a b.png", "mini:/x/y.png"])
        #expect(description == "/usr/bin/scp '/tmp/a b.png' mini:/x/y.png")
    }

    @Test("命令描述：空参数列表")
    func describeEmptyCommand() {
        #expect(LogFormatter.describeCommand([]) == "")
    }
}
