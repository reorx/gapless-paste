import AppKit
import GaplessPasteCore

// 配置读写：~/Library/Application Support/GaplessPaste/config.json
// 首启无配置文件：写入示例模板并打开它；解析失败保留错误态供菜单展示

@MainActor
final class ConfigStore {
    let configURL: URL
    private(set) var lastResult: Result<Config, Error>

    init() {
        let supportDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GaplessPaste", isDirectory: true)
        configURL = supportDir.appendingPathComponent("config.json")
        lastResult = .success(Config(machines: []))
        load()
    }

    /// 返回 true 表示这是首启（刚写入模板并打开了它）
    @discardableResult
    func load() -> Bool {
        var isFirstLaunch = false
        if !FileManager.default.fileExists(atPath: configURL.path) {
            try? FileManager.default.createDirectory(
                at: configURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? Config.templateJSON.write(to: configURL, atomically: true, encoding: .utf8)
            isFirstLaunch = true
        }
        do {
            lastResult = .success(try Config.parse(Data(contentsOf: configURL)))
        } catch {
            lastResult = .failure(error)
        }
        if isFirstLaunch {
            openInEditor()
        }
        return isFirstLaunch
    }

    func openInEditor() {
        NSWorkspace.shared.open(configURL)
    }
}
