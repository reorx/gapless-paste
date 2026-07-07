import AppKit
import GaplessPasteCore

// 配置读写：~/Library/Application Support/GaplessPaste/config.json
// 首启无配置文件：写入示例模板（AppDelegate 据 isFirstLaunch 打开设置窗口引导）；
// 解析失败保留错误态供菜单展示

@MainActor
final class ConfigStore {
    let configURL: URL
    private(set) var lastResult: Result<Config, Error>
    /// 本次启动是首启（刚写入示例模板）
    private(set) var isFirstLaunch = false

    init() {
        let supportDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GaplessPaste", isDirectory: true)
        configURL = supportDir.appendingPathComponent("config.json")
        lastResult = .success(Config(machines: []))
        isFirstLaunch = load()
    }

    /// 返回 true 表示这是首启（刚写入模板）
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
        return isFirstLaunch
    }

    /// 设置界面保存：校验 + 序列化 + 原子写盘，成功后内存态同步更新
    func save(_ config: Config) throws {
        let data = try config.serialize()
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: configURL, options: .atomic)
        lastResult = .success(config)
    }

    func openInEditor() {
        NSWorkspace.shared.open(configURL)
    }
}
