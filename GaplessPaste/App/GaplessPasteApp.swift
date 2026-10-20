import AppKit
import SwiftUI

// 菜单栏 app：project.yml 设 LSUIElement: true，启动时无 Dock 图标（.accessory）；
// 预览/设置等普通窗口打开期间由 DockPresence 切成 .regular（Dock 图标 + 主菜单栏 + ⌘Tab），
// 全部关闭后退回 .accessory。
// 用 NSStatusItem 而非 MenuBarExtra：M3 需要在 status item button 上注册拖拽 drop target

@main
struct GaplessPasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                // 默认「Settings… ⌘,」会打开上面的空 Settings 场景，改为转发到真正的设置窗口
                CommandGroup(replacing: .appSettings) {
                    Button("设置…") { delegate.openSettings() }
                        .keyboardShortcut(",")
                }
                CommandGroup(replacing: .help) {}
            }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState!
    private var menuController: StatusMenuController!
    private var updateController: UpdateController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState = AppState()
        updateController = UpdateController()
        menuController = StatusMenuController(appState: appState, updateController: updateController)
        #if DEBUG
        DebugHooks.install(appState: appState, menuController: menuController)
        #endif
        // 首启（刚写入示例模板）：打开设置窗口引导用户配置，取代旧的「打开配置文件」
        if appState.configStore.isFirstLaunch {
            appState.openSettings()
        }
    }

    /// 点 Dock 图标：有可见窗口时激活 app 已足够；全部最小化时恢复最近使用的窗口。
    /// 返回 false 不走 SwiftUI 默认处理（它会尝试打开场景窗口）
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            DockPresence.focusMostRecent()
        }
        return false
    }

    func openSettings() {
        appState.openSettings()
    }
}
