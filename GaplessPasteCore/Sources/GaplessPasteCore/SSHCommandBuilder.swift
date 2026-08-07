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

    // MARK: - ControlPath 长度预算
    // unix socket 的 sun_path 上限 104 字节（含 NUL 终止符），可用 103。
    // %C 展开为 40 字符哈希；ssh 建 listener 时会先用「最终名 + .s<16 随机字符>」
    // 的临时名（共 17 字符后缀），必须一并预留，否则报
    // "unix_listener: path ... too long for Unix domain socket"

    public static let maxUnixSocketPathLength = 103
    private static let controlPathOverhead = 1 + 40 + 17 // "/" + %C 哈希 + 临时后缀

    public static func predictedSocketPathLength(forDirectory directory: String) -> Int {
        directory.utf8.count + controlPathOverhead
    }

    public static func isUsableControlPathDirectory(_ directory: String) -> Bool {
        predictedSocketPathLength(forDirectory: directory) <= maxUnixSocketPathLength
    }

    /// 默认 socket 目录：/tmp/gaplesspaste-<uid>。
    /// 选 /tmp 是因为 Caches/Application Support 前缀都太长（见上方预算）；
    /// 目录须由 app 侧以 0700 创建，保证用户私有
    public static func defaultControlPathDirectory(uid: UInt32) -> String {
        "/tmp/gaplesspaste-\(uid)"
    }

    /// 幂等确保 socket 目录存在（0700）。macOS 周期清理会删掉 /tmp 下
    /// 数天未访问的目录，长时间挂机后 ControlPath 父目录消失会导致
    /// "unix_listener: cannot bind to path ..."，因此每次执行 ssh/scp 前都应调用
    public func ensureControlPathDirectory(fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(
            atPath: controlPathDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }
}
