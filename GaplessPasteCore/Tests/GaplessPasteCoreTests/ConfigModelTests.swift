import Foundation
import Testing
@testable import GaplessPasteCore

@Suite("配置模型：解析与校验")
struct ConfigModelTests {
    @Test("解析标准配置，忽略 _readme 与未知键")
    func parseSampleConfig() throws {
        let json = """
        {
          "_readme": "说明文字，解析时忽略",
          "futureKey": 42,
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
        let config = try Config.parse(Data(json.utf8))
        #expect(config.machines.count == 1)
        #expect(config.machines[0].name == "mini")
        #expect(config.machines[0].sshAlias == "mini")
        #expect(config.machines[0].directories.count == 2)
        #expect(config.machines[0].directories[0].path == "~/claude-inbox")
    }

    @Test("machines 为空数组是合法配置（菜单显示引导态）")
    func emptyMachinesIsValid() throws {
        let config = try Config.parse(Data(#"{"machines": []}"#.utf8))
        #expect(config.machines.isEmpty)
    }

    @Test("非法 JSON 抛错")
    func invalidJSONThrows() {
        #expect(throws: (any Error).self) {
            try Config.parse(Data("not json".utf8))
        }
    }

    @Test("机器 name 为空 → 校验失败")
    func emptyMachineNameFails() {
        let json = #"{"machines": [{"name": "", "sshAlias": "mini", "directories": [{"name": "d", "path": "/x"}]}]}"#
        #expect(throws: ConfigError.self) {
            try Config.parse(Data(json.utf8))
        }
    }

    @Test("机器 sshAlias 为空 → 校验失败")
    func emptySSHAliasFails() {
        let json = #"{"machines": [{"name": "mini", "sshAlias": "", "directories": [{"name": "d", "path": "/x"}]}]}"#
        #expect(throws: ConfigError.self) {
            try Config.parse(Data(json.utf8))
        }
    }

    @Test("目录 path 为空 → 校验失败")
    func emptyDirectoryPathFails() {
        let json = #"{"machines": [{"name": "mini", "sshAlias": "mini", "directories": [{"name": "d", "path": ""}]}]}"#
        #expect(throws: ConfigError.self) {
            try Config.parse(Data(json.utf8))
        }
    }

    @Test("首启模板本身可解析且通过校验")
    func templateParses() throws {
        let config = try Config.parse(Data(Config.templateJSON.utf8))
        #expect(!config.machines.isEmpty)
        #expect(!config.machines[0].directories.isEmpty)
    }
}

@Suite("配置模型：GUI 编辑与序列化")
struct ConfigSerializationTests {
    private var sample: Config {
        Config(machines: [
            Machine(name: "mini", sshAlias: "mini-alias", directories: [
                RemoteDirectory(name: "inbox", path: "~/claude-inbox"),
                RemoteDirectory(name: "screenshots", path: "~/claude-inbox/screenshots"),
            ]),
            Machine(name: "vps", sshAlias: "vps", directories: []),
        ])
    }

    @Test("serialize → parse 往返等值（机器与目录顺序保持）")
    func roundTrip() throws {
        let data = try sample.serialize()
        let parsed = try Config.parse(data)
        #expect(parsed == sample)
        #expect(parsed.machines.map(\.name) == ["mini", "vps"])
        #expect(parsed.machines[0].directories.map(\.name) == ["inbox", "screenshots"])
    }

    @Test("serialize 输出人类可读：多行缩进、~/ 不转义")
    func serializeIsHumanReadable() throws {
        let text = String(decoding: try sample.serialize(), as: UTF8.self)
        #expect(text.contains("\n"))
        #expect(text.contains("~/claude-inbox"))
        #expect(!text.contains("\\/"))
    }

    @Test("serialize 校验失败时抛错，不产出非法配置文件")
    func serializeValidatesFirst() {
        let bad = Config(machines: [Machine(name: "", sshAlias: "x", directories: [])])
        #expect(throws: ConfigError.self) {
            try bad.serialize()
        }
    }

    @Test("模型属性可变，支持 GUI 就地编辑")
    func modelIsMutable() {
        var config = sample
        config.machines[0].name = "mini2"
        config.machines[0].sshAlias = "mini2"
        config.machines[0].directories[0].path = "~/inbox2"
        config.machines.append(Machine(name: "new", sshAlias: "new", directories: []))
        #expect(config.machines.count == 3)
        #expect(config.machines[0].directories[0].path == "~/inbox2")
    }
}
