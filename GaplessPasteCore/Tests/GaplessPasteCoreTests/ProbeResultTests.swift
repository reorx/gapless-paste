import Foundation
import Testing
@testable import GaplessPasteCore

@Suite("远端探测：$HOME/uname 解析与路径展开")
struct ProbeResultTests {
    @Test("解析标准两行输出")
    func parseStandardOutput() {
        let result = ProbeResult.parse("/Users/reorx\nDarwin\n")
        #expect(result == ProbeResult(home: "/Users/reorx", unameString: "Darwin"))
        #expect(result?.isDarwin == true)
    }

    @Test("解析 Linux 输出")
    func parseLinux() {
        let result = ProbeResult.parse("/home/reorx\nLinux\n")
        #expect(result?.isDarwin == false)
    }

    @Test("容忍多余空行与首尾空白")
    func parseTolerantOfBlankLines() {
        let result = ProbeResult.parse("\n  /Users/reorx  \n\nDarwin  \n\n")
        #expect(result == ProbeResult(home: "/Users/reorx", unameString: "Darwin"))
    }

    @Test("行数不足或 home 非绝对路径 → nil")
    func parseGarbageReturnsNil() {
        #expect(ProbeResult.parse("") == nil)
        #expect(ProbeResult.parse("Darwin\n") == nil)
        #expect(ProbeResult.parse("not-a-path\nDarwin\n") == nil)
    }

    @Test("~ 前缀展开为绝对路径")
    func expandTildePaths() {
        let probe = ProbeResult(home: "/Users/reorx", unameString: "Darwin")
        #expect(probe.expandPath("~/claude-inbox") == "/Users/reorx/claude-inbox")
        #expect(probe.expandPath("~") == "/Users/reorx")
        #expect(probe.expandPath("/var/tmp") == "/var/tmp")
    }

    @Test("探测命令一次拿全 $HOME 与 uname")
    func probeCommandContent() {
        #expect(ProbeResult.shellCommand == #"echo "$HOME"; uname"#)
    }
}
