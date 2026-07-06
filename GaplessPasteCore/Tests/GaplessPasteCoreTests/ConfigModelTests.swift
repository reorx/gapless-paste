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
