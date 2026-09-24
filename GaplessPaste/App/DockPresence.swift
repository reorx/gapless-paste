import AppKit

// 普通窗口（预览/设置）打开期间让 app 以 Dock app 形式存在：
// 有被追踪窗口时 activation policy 为 .regular（Dock 图标 + 主菜单栏 + ⌘Tab + ⌘` 切窗），
// 最后一个关闭后退回 .accessory。LSUIElement 仍为 true，启动时不出现 Dock 图标。
// 浮窗类（RenamePopup / DropPanel / NSAlert 模态）不接入。

@MainActor
enum DockPresence {
    private struct Entry {
        weak var window: NSWindow?
        var observers: [NSObjectProtocol]
    }

    /// 按最近使用排序，末尾为最近获得焦点的窗口
    private static var entries: [Entry] = []

    static func track(_ window: NSWindow) {
        if !entries.contains(where: { $0.window === window }) {
            let center = NotificationCenter.default
            let closeObserver = center.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak window] _ in
                MainActor.assumeIsolated {
                    if let window { untrack(window) }
                }
            }
            let keyObserver = center.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { [weak window] _ in
                MainActor.assumeIsolated {
                    if let window { markRecent(window) }
                }
            }
            entries.append(Entry(window: window, observers: [closeObserver, keyObserver]))
        }
        markRecent(window)
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
    }

    /// Dock 点击且无可见窗口（全部最小化）时恢复最近使用的窗口
    static func focusMostRecent() {
        guard let window = entries.last?.window else { return }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func markRecent(_ window: NSWindow) {
        guard let index = entries.firstIndex(where: { $0.window === window }),
              index != entries.count - 1
        else { return }
        entries.append(entries.remove(at: index))
    }

    private static func untrack(_ window: NSWindow) {
        guard let index = entries.firstIndex(where: { $0.window === window }) else { return }
        for observer in entries[index].observers {
            NotificationCenter.default.removeObserver(observer)
        }
        entries.remove(at: index)
        guard entries.isEmpty else { return }
        // willClose 时窗口仍在屏幕上，推迟到下一轮 runloop 再切回 accessory；
        // 期间若又打开了新窗口则保持 regular
        DispatchQueue.main.async {
            if entries.isEmpty {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
