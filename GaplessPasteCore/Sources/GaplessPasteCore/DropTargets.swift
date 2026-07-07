import Foundation

// M3 拖拽上传（路径 C）：配置 → DropPanel 的行模型。
// 所有「机器 × 目录」平铺成行（spec：不按机器嵌套分组），每行是独立 drop target

public struct DropTargetRow: Equatable, Sendable {
    public let machine: Machine
    public let directory: RemoteDirectory

    public init(machine: Machine, directory: RemoteDirectory) {
        self.machine = machine
        self.directory = directory
    }

    public var label: String { "\(machine.name)/\(directory.name)" }
}

public enum DropTargets {
    public static func rows(from config: Config) -> [DropTargetRow] {
        config.machines.flatMap { machine in
            machine.directories.map { DropTargetRow(machine: machine, directory: $0) }
        }
    }
}
