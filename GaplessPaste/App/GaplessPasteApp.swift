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
    }
}
