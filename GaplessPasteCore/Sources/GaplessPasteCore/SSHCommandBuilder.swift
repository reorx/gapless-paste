import Foundation

// 传输层走系统 /usr/bin/ssh 与 /usr/bin/scp 子进程，天然继承 ~/.ssh/config。
// 这里只负责纯函数式的参数数组构建：ControlMaster 复用选项、远端路径转义。
// 注意：controlPathDirectory 不能含空格（ssh 的 -o 值按配置行分词），
// app 侧应传 ~/Library/Caches/com.reorx.gaplesspaste/sockets 这类无空格路径。

public struct SSHCommandBuilder: Sendable {
    public let controlPathDirectory: String

    public init(controlPathDirectory: String) {
        self.controlPathDirectory = controlPathDirectory
    }

    /// BatchMode 让免密失败时立即报错而不是挂起等输入；
    /// ControlMaster 复用连接，首连后重复上传毫秒级，适配「截图连发」
    public var baseOptions: [String] {
        [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=10",
            "-o", "ControlMaster=auto",
            "-o", "ControlPath=\(controlPathDirectory)/%C",
            "-o", "ControlPersist=600",
        ]
    }

    public func sshCommand(host: String, remoteCommand: String) -> [String] {
        ["/usr/bin/ssh"] + baseOptions + [host, remoteCommand]
    }

    /// macOS 的 scp 默认走 SFTP 协议，远端路径无 shell 展开，按原样单参数传递即可
    public func scpCommand(localPath: String, host: String, remotePath: String) -> [String] {
        ["/usr/bin/scp"] + baseOptions + [localPath, "\(host):\(remotePath)"]
    }

    public func probeCommand(host: String) -> [String] {
        sshCommand(host: host, remoteCommand: ProbeResult.shellCommand)
    }

    /// 重名探测：exit 0 = 存在
    public func testExistsCommand(host: String, remotePath: String) -> [String] {
        sshCommand(host: host, remoteCommand: "test -e \(Self.shellQuote(remotePath))")
    }

    public func mkdirCommand(host: String, remoteDirectory: String) -> [String] {
        sshCommand(host: host, remoteCommand: "mkdir -p \(Self.shellQuote(remoteDirectory))")
    }

    /// POSIX 单引号转义：内部 ' 变为 '\''
    public static func shellQuote(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
