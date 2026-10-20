import AppKit

// 普通窗口（预览/设置/传输详情）打开期间让 app 以 Dock app 形式存在：
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
    private static var pendingDemotion: DispatchWorkItem?

    #if DEBUG
    private(set) static var debugTransitions: [String] = []
    private static func recordTransition(_ value: String) {
        debugTransitions = Array((debugTransitions + [value]).suffix(40))
    }
    static var debugWindowTitles: [String] {
        entries.map { $0.window?.title ?? "<released>" }
    }
    static func debugCloseWindows() {
        for window in entries.compactMap(\.window) { window.close() }
    }
    #endif

    static func track(_ window: NSWindow) {
        pendingDemotion?.cancel()
        pendingDemotion = nil
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
        #if DEBUG
        recordTransition("track \(window.title): count=\(entries.count), policy=\(NSApp.activationPolicy().rawValue)")
        #endif
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
        #if DEBUG
        recordTransition("untrack \(window.title): count=\(entries.count)")
        #endif
        guard entries.isEmpty else { return }
        scheduleDemotion()
    }

    private static func scheduleDemotion(attemptsRemaining: Int = 5) {
        // willClose 时 AppKit 尚在收尾窗口及激活状态，立即转换可能返回 false 并回滚。
        // 给系统短暂收尾时间；转换被拒时退出激活状态后有限重试，不做空闲轮询。
        let work = DispatchWorkItem {
            pendingDemotion = nil
            guard entries.isEmpty else { return }
            let changed = NSApp.setActivationPolicy(.accessory)
            #if DEBUG
            recordTransition("accessory: accepted=\(changed), policy=\(NSApp.activationPolicy().rawValue)")
            #endif
            if !changed, attemptsRemaining > 1 {
                NSApp.deactivate()
                scheduleDemotion(attemptsRemaining: attemptsRemaining - 1)
            }
        }
        pendingDemotion = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }
}
