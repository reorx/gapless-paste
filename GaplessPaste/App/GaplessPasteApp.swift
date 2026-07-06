import AppKit
import SwiftUI
import GaplessPasteCore

// 菜单栏 accessory app（project.yml 已设 LSUIElement: true，无 Dock 图标）
@main
struct GaplessPasteApp: App {
    var body: some Scene {
        MenuBarExtra {
            Text(Greeting().message(for: "GaplessPaste"))

            Divider()

            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            Image(systemName: "sparkles")
        }
    }
}
