import Foundation

// 配置模型：~/Library/Application Support/GaplessPaste/config.json
// JSONDecoder 默认忽略未知键，顶层 _readme 说明字段天然被跳过

public struct RemoteDirectory: Codable, Equatable, Sendable {
    public let name: String
    public let path: String

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

public struct Machine: Codable, Equatable, Sendable {
    public let name: String
    public let sshAlias: String
    public let directories: [RemoteDirectory]

    public init(name: String, sshAlias: String, directories: [RemoteDirectory]) {
        self.name = name
        self.sshAlias = sshAlias
        self.directories = directories
    }
}

public enum ConfigError: Error, Equatable, LocalizedError {
    case emptyMachineName
    case emptySSHAlias(machine: String)
    case emptyDirectoryName(machine: String)
    case emptyDirectoryPath(machine: String, directory: String)

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
        }
    }
}

public struct Config: Codable, Equatable, Sendable {
    public let machines: [Machine]

    public init(machines: [Machine]) {
        self.machines = machines
    }

    /// 解码 + 校验一步完成
    public static func parse(_ data: Data) throws -> Config {
        let config = try JSONDecoder().decode(Config.self, from: data)
        try config.validate()
        return config
    }

    public func validate() throws {
        for machine in machines {
            guard !machine.name.isEmpty else { throw ConfigError.emptyMachineName }
            guard !machine.sshAlias.isEmpty else { throw ConfigError.emptySSHAlias(machine: machine.name) }
            for directory in machine.directories {
                guard !directory.name.isEmpty else { throw ConfigError.emptyDirectoryName(machine: machine.name) }
                guard !directory.path.isEmpty else {
                    throw ConfigError.emptyDirectoryPath(machine: machine.name, directory: directory.name)
                }
            }
        }
    }

    /// 首启写入的示例模板（标准 JSON 无注释，说明放 _readme）
    public static let templateJSON = """
    {
      "_readme": "GaplessPaste 配置。sshAlias 对应 ~/.ssh/config 的 Host 条目（认证/端口/跳板全由 ssh config 负责）；path 支持 ~/ 前缀，运行时用远端 $HOME 展开。改完后在菜单里点「重载配置」生效。",
      "machines": [
        {
          "name": "mini",
          "sshAlias": "mini",
          "directories": [
            { "name": "inbox", "path": "~/claude-inbox" },
            { "name": "screenshots", "path": "~/claude-inbox/screenshots" }
          ]
        }
      ]
    }
    """
}
