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

@Suite("配置模型：默认目录角色 default_of")
struct DirectoryRoleTests {
    @Test("解析 default_of = FILE / IMAGE")
    func parseRoles() throws {
        let json = """
        {
          "machines": [
            {
              "name": "mini", "sshAlias": "mini",
              "directories": [
                { "name": "inbox", "path": "~/in", "default_of": "FILE" },
                { "name": "shots", "path": "~/shots", "default_of": "IMAGE" }
              ]
            }
          ]
        }
        """
        let dirs = try Config.parse(Data(json.utf8)).machines[0].directories
        #expect(dirs[0].defaultOf == .file)
        #expect(dirs[1].defaultOf == .image)
    }

    @Test("缺省 default_of → nil（普通目录）")
    func missingRoleIsNil() throws {
        let json = #"{"machines":[{"name":"m","sshAlias":"m","directories":[{"name":"d","path":"/x"}]}]}"#
        let config = try Config.parse(Data(json.utf8))
        #expect(config.machines[0].directories[0].defaultOf == nil)
    }

    @Test("非法 default_of 值 → 解析失败")
    func invalidRoleThrows() {
        let json = #"{"machines":[{"name":"m","sshAlias":"m","directories":[{"name":"d","path":"/x","default_of":"VIDEO"}]}]}"#
        #expect(throws: (any Error).self) {
            try Config.parse(Data(json.utf8))
        }
    }

    @Test("同一机器两个 FILE 默认 → 校验失败")
    func duplicateFileDefaultFails() {
        let json = """
        {"machines":[{"name":"m","sshAlias":"m","directories":[
          {"name":"a","path":"/a","default_of":"FILE"},
          {"name":"b","path":"/b","default_of":"FILE"}
        ]}]}
        """
        #expect(throws: ConfigError.self) {
            try Config.parse(Data(json.utf8))
        }
    }

    @Test("同一机器两个 IMAGE 默认 → 校验失败")
    func duplicateImageDefaultFails() {
        let json = """
        {"machines":[{"name":"m","sshAlias":"m","directories":[
          {"name":"a","path":"/a","default_of":"IMAGE"},
          {"name":"b","path":"/b","default_of":"IMAGE"}
        ]}]}
        """
        #expect(throws: ConfigError.self) {
            try Config.parse(Data(json.utf8))
        }
    }

    @Test("同机器 FILE + IMAGE 各一 + 普通目录 → 合法")
    func oneEachIsValid() throws {
        let json = """
        {"machines":[{"name":"m","sshAlias":"m","directories":[
          {"name":"a","path":"/a","default_of":"FILE"},
          {"name":"b","path":"/b","default_of":"IMAGE"},
          {"name":"c","path":"/c"}
        ]}]}
        """
        let config = try Config.parse(Data(json.utf8))
        #expect(config.machines[0].directories.count == 3)
    }

    @Test("不同机器可各自拥有 FILE 默认（唯一性仅限每台机器内）")
    func perMachineScope() throws {
        let json = """
        {"machines":[
          {"name":"m1","sshAlias":"m1","directories":[{"name":"a","path":"/a","default_of":"FILE"}]},
          {"name":"m2","sshAlias":"m2","directories":[{"name":"b","path":"/b","default_of":"FILE"}]}
        ]}
        """
        let config = try Config.parse(Data(json.utf8))
        #expect(config.machines.count == 2)
    }

    @Test("defaultDirectory(for:) 返回该机器对应角色目录，无则 nil")
    func lookupHelper() {
        let machine = Machine(name: "m", sshAlias: "m", directories: [
            RemoteDirectory(name: "a", path: "/a", defaultOf: .file),
            RemoteDirectory(name: "b", path: "/b"),
        ])
        #expect(machine.defaultDirectory(for: .file)?.name == "a")
        #expect(machine.defaultDirectory(for: .image) == nil)
    }

    @Test("serialize 往返保留 default_of，普通目录不写该键")
    func roundTripAndOmitNil() throws {
        let config = Config(machines: [
            Machine(name: "m", sshAlias: "m", directories: [
                RemoteDirectory(name: "a", path: "/a", defaultOf: .image),
                RemoteDirectory(name: "b", path: "/b"),
            ]),
        ])
        let data = try config.serialize()
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("default_of"))
        #expect(text.contains("IMAGE"))
        // 只有目录 a 携带 default_of，普通目录 b 不产出该键
        #expect(text.components(separatedBy: "default_of").count - 1 == 1)
        let parsed = try Config.parse(data)
        #expect(parsed == config)
        #expect(parsed.machines[0].directories[1].defaultOf == nil)
    }

    @Test("首启模板：inbox=FILE，screenshots=IMAGE")
    func templateRoles() throws {
        let dirs = try Config.parse(Data(Config.templateJSON.utf8)).machines[0].directories
        #expect(dirs.first { $0.name == "inbox" }?.defaultOf == .file)
        #expect(dirs.first { $0.name == "screenshots" }?.defaultOf == .image)
    }
}
