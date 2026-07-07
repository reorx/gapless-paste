import Testing
@testable import GaplessPasteCore

// M3 拖拽上传：DropPanel 把配置里所有「机器 × 目录」平铺成行，
// 每行是独立 drop target（spec 触发路径 C）

@Suite("DropTargets")
struct DropTargetsTests {
    private let mini = Machine(
        name: "mini",
        sshAlias: "mini",
        directories: [
            RemoteDirectory(name: "inbox", path: "~/claude-inbox"),
            RemoteDirectory(name: "screenshots", path: "~/claude-inbox/screenshots"),
        ]
    )
    private let linux = Machine(
        name: "vps",
        sshAlias: "vps",
        directories: [RemoteDirectory(name: "drop", path: "/srv/drop")]
    )

    @Test("多机器多目录按配置顺序平铺成行")
    func flattensMachinesAndDirectoriesInOrder() {
        let rows = DropTargets.rows(from: Config(machines: [mini, linux]))
        #expect(rows.count == 3)
        #expect(rows[0].machine == mini && rows[0].directory == mini.directories[0])
        #expect(rows[1].machine == mini && rows[1].directory == mini.directories[1])
        #expect(rows[2].machine == linux && rows[2].directory == linux.directories[0])
    }

    @Test("行标签为「机器名/目录名」")
    func rowLabelIsMachineSlashDirectory() {
        let rows = DropTargets.rows(from: Config(machines: [mini]))
        #expect(rows[0].label == "mini/inbox")
        #expect(rows[1].label == "mini/screenshots")
    }

    @Test("无目录的机器不产生行")
    func machineWithoutDirectoriesYieldsNoRows() {
        let empty = Machine(name: "bare", sshAlias: "bare", directories: [])
        let rows = DropTargets.rows(from: Config(machines: [empty, linux]))
        #expect(rows.map(\.label) == ["vps/drop"])
    }

    @Test("空配置无行")
    func emptyConfigYieldsNoRows() {
        #expect(DropTargets.rows(from: Config(machines: [])).isEmpty)
    }
}
