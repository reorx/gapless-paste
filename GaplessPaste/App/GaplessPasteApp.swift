import AppKit
import SwiftUI

// 菜单栏 accessory app（project.yml 已设 LSUIElement: true，无 Dock 图标）。
// 用 NSStatusItem 而非 MenuBarExtra：M3 需要在 status item button 上注册拖拽 drop target

@main
struct GaplessPasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState!
    private var menuController: StatusMenuController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState = AppState()
        menuController = StatusMenuController(appState: appState)
        #if DEBUG
        DebugHooks.install()
        #endif
        // 首启（刚写入示例模板）：打开设置窗口引导用户配置，取代旧的「打开配置文件」
        if appState.configStore.isFirstLaunch {
            appState.openSettings()
        }
    }
}
