import Foundation
import Testing
@testable import GaplessPasteCore

@Suite("SSH 命令构建：ControlMaster 选项与转义")
struct SSHCommandBuilderTests {
    let builder = SSHCommandBuilder(controlPathDirectory: "/tmp/sockets")

    @Test("基础选项：BatchMode、超时、ControlMaster 复用")
    func baseOptions() {
        let options = builder.baseOptions
        #expect(options.contains("BatchMode=yes"))
        #expect(options.contains("ConnectTimeout=10"))
        #expect(options.contains("ControlMaster=auto"))
        #expect(options.contains("ControlPath=/tmp/sockets/%C"))
        #expect(options.contains("ControlPersist=600"))
        // 每个选项前都有 -o
        #expect(options.filter { $0 == "-o" }.count == 5)
    }

    @Test("ssh 命令结构：可执行路径 + 选项 + host + 远端命令")
    func sshCommandShape() {
        let argv = builder.sshCommand(host: "mini", remoteCommand: "uname")
        #expect(argv.first == "/usr/bin/ssh")
        #expect(argv.last == "uname")
        #expect(argv[argv.count - 2] == "mini")
    }

    @Test("scp 上传单文件到指定远端路径")
    func scpCommandShape() {
        let argv = builder.scpCommand(localPath: "/tmp/shot.png", host: "mini", remotePath: "/Users/reorx/claude-inbox/shot.png")
        #expect(argv.first == "/usr/bin/scp")
        #expect(argv[argv.count - 2] == "/tmp/shot.png")
        #expect(argv.last == "mini:/Users/reorx/claude-inbox/shot.png")
    }

    @Test("shell 单引号转义")
    func shellQuote() {
        #expect(SSHCommandBuilder.shellQuote("plain") == "'plain'")
        #expect(SSHCommandBuilder.shellQuote("a b") == "'a b'")
        #expect(SSHCommandBuilder.shellQuote("it's") == #"'it'\''s'"#)
    }

    @Test("探测命令")
    func probeCommand() {
        let argv = builder.probeCommand(host: "mini")
        #expect(argv.last == #"echo "$HOME"; uname"#)
    }

    @Test("重名探测：test -e 加引号路径")
    func testExistsCommand() {
        let argv = builder.testExistsCommand(host: "mini", remotePath: "/a/b c.png")
        #expect(argv.last == "test -e '/a/b c.png'")
    }

    @Test("目录确保：mkdir -p 加引号路径")
    func mkdirCommand() {
        let argv = builder.mkdirCommand(host: "mini", remoteDirectory: "/a/claude inbox")
        #expect(argv.last == "mkdir -p '/a/claude inbox'")
    }

    // 复现线上 bug：Caches 目录 58 字符 + /%C(40) + ssh 临时后缀(17) = 116，
    // 超过 unix socket sun_path 上限，报 "unix_listener: path ... too long"
    @Test("Caches 下的 socket 目录超长，不可用作 ControlPath")
    func cachesDirectoryTooLongForControlPath() {
        let cachesDir = "/Users/reorx/Library/Caches/com.reorx.gaplesspaste/sockets"
        #expect(SSHCommandBuilder.predictedSocketPathLength(forDirectory: cachesDir) > SSHCommandBuilder.maxUnixSocketPathLength)
        #expect(!SSHCommandBuilder.isUsableControlPathDirectory(cachesDir))
    }

    @Test("默认 socket 目录：/tmp/gaplesspaste-<uid>，长度可用")
    func defaultControlPathDirectoryIsUsable() {
        let dir = SSHCommandBuilder.defaultControlPathDirectory(uid: 501)
        #expect(dir == "/tmp/gaplesspaste-501")
        #expect(SSHCommandBuilder.isUsableControlPathDirectory(dir))
        // 六位数 uid 也不越界
        #expect(SSHCommandBuilder.isUsableControlPathDirectory(SSHCommandBuilder.defaultControlPathDirectory(uid: 999_999)))
    }

    @Test("长度预算边界：103 字节含目录 + / + 40 字符哈希 + 17 字符临时后缀")
    func socketPathLengthBoundary() {
        // 103 - 1 - 40 - 17 = 45：目录 ≤ 45 字符可用，46 不可用
        #expect(SSHCommandBuilder.isUsableControlPathDirectory(String(repeating: "a", count: 45)))
        #expect(!SSHCommandBuilder.isUsableControlPathDirectory(String(repeating: "a", count: 46)))
    }
}
