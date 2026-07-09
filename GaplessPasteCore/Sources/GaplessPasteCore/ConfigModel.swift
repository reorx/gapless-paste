import Foundation

// 配置模型：~/Library/Application Support/GaplessPaste/config.json
// JSONDecoder 默认忽略未知键，顶层 _readme 说明字段天然被跳过

/// 快速上传的默认目录角色：文件引用走 .file、图像数据走 .image。
/// JSON 里为大写字符串 "FILE" / "IMAGE"，缺省表示普通目录（无默认角色）。
public enum DirectoryRole: String, Codable, Equatable, Sendable, CaseIterable {
    case file = "FILE"
    case image = "IMAGE"
}

public struct RemoteDirectory: Codable, Equatable, Sendable {
    public var name: String
    public var path: String
    /// 快速上传默认落点角色；nil 为普通目录。同一机器内每个角色至多一个（Config.validate 保证）
    public var defaultOf: DirectoryRole?

    public init(name: String, path: String, defaultOf: DirectoryRole? = nil) {
        self.name = name
        self.path = path
        self.defaultOf = defaultOf
    }

    // defaultOf 是 Optional：解码时缺省即 nil，编码时 nil 自动省略该键（普通目录不写 default_of）
    private enum CodingKeys: String, CodingKey {
        case name
        case path
        case defaultOf = "default_of"
    }
}

public struct Machine: Codable, Equatable, Sendable {
    public var name: String
    public var sshAlias: String
    public var directories: [RemoteDirectory]

    public init(name: String, sshAlias: String, directories: [RemoteDirectory]) {
        self.name = name
        self.sshAlias = sshAlias
        self.directories = directories
    }

    /// 该机器某角色的默认目录（Config.validate 保证每角色至多一个）
    public func defaultDirectory(for role: DirectoryRole) -> RemoteDirectory? {
        directories.first { $0.defaultOf == role }
    }
}

public enum ConfigError: Error, Equatable, LocalizedError {
    case emptyMachineName
    case emptySSHAlias(machine: String)
    case emptyDirectoryName(machine: String)
    case emptyDirectoryPath(machine: String, directory: String)
    case duplicateDefaultDirectory(machine: String, role: DirectoryRole)

    public var errorDescription: String? {
        switch self {
        case .emptyMachineName:
            return "机器 name 不能为空"
        case .emptySSHAlias(let machine):
            return "机器 \(machine) 的 sshAlias 不能为空"
        case .emptyDirectoryName(let machine):
            return "机器 \(machine) 存在 name 为空的目录"
        case .emptyDirectoryPath(let machine, let directory):
            return "机器 \(machine) 的目录 \(directory) path 不能为空"
        case .duplicateDefaultDirectory(let machine, let role):
            let label = role == .file ? "文件" : "图像"
            return "机器 \(machine) 有多个\(label)默认目录（每台机器每类至多一个）"
        }
    }
}

public struct Config: Codable, Equatable, Sendable {
    public var machines: [Machine]

    public init(machines: [Machine]) {
        self.machines = machines
    }

    /// 解码 + 校验一步完成
    public static func parse(_ data: Data) throws -> Config {
        let config = try JSONDecoder().decode(Config.self, from: data)
        try config.validate()
        return config
    }

    /// 校验 + 编码一步完成（GUI 保存路径）：pretty JSON，字段序稳定，~/ 不转义
    public func serialize() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public func validate() throws {
        for machine in machines {
            guard !machine.name.isEmpty else { throw ConfigError.emptyMachineName }
            guard !machine.sshAlias.isEmpty else { throw ConfigError.emptySSHAlias(machine: machine.name) }
            var seenRoles = Set<DirectoryRole>()
            for directory in machine.directories {
                guard !directory.name.isEmpty else { throw ConfigError.emptyDirectoryName(machine: machine.name) }
                guard !directory.path.isEmpty else {
                    throw ConfigError.emptyDirectoryPath(machine: machine.name, directory: directory.name)
                }
                if let role = directory.defaultOf, !seenRoles.insert(role).inserted {
                    throw ConfigError.duplicateDefaultDirectory(machine: machine.name, role: role)
                }
            }
        }
    }

    /// 首启写入的示例模板（标准 JSON 无注释，说明放 _readme）
    public static let templateJSON = """
    {
      "_readme": "GaplessPaste 配置。sshAlias 对应 ~/.ssh/config 的 Host 条目（认证/端口/跳板全由 ssh config 负责）；path 支持 ~/ 前缀，运行时用远端 $HOME 展开。default_of 可选 FILE/IMAGE，标记该目录为「快速上传」时文件/图像的默认落点（每台机器每类至多一个）。改完后在菜单里点「重载配置」生效。",
      "machines": [
        {
          "name": "mini",
          "sshAlias": "mini",
          "directories": [
            { "name": "inbox", "path": "~/claude-inbox", "default_of": "FILE" },
            { "name": "screenshots", "path": "~/claude-inbox/screenshots", "default_of": "IMAGE" }
          ]
        }
      ]
    }
    """
}
