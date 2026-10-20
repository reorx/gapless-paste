#if DEBUG
import AppKit

// DEBUG 专用自动化验收钩子：分布式通知触发窗口自截图。
// app 截取自己的窗口（cacheDisplay）不需要 Screen Recording TCC 权限，
// 供无授权终端环境下的自动化验收取证。Release 构建不包含本文件逻辑。
//
// 触发（swift 脚本 / 其他进程）：
//   DistributedNotificationCenter.default().postNotificationName(
//       .init("com.reorx.gaplesspaste.debug.capture"),
//       object: "/输出目录",
//       userInfo: nil, deliverImmediately: true)
// 每个可见窗口写为 <输出目录>/window-<序号>-<标题>.png
//
// 预览窗口钩子（绕过模态路径弹窗，AX 驱动 NSAlert 不可靠）：
//   通知名 com.reorx.gaplesspaste.debug.preview，object = "<机器名>|<远端路径>"
//
// 预览窗口动作钩子（锁屏等 AX 不可用时驱动最近打开的预览窗口，指令见 PreviewWindowModel.debugPerform）：
//   通知名 com.reorx.gaplesspaste.debug.preview-action，object = "up" / "enter|<路径>" / "select|<路径>…" / "refresh" / "dump"

@MainActor
enum DebugHooks {
    static func install(appState: AppState, menuController: StatusMenuController) {
        DistributedNotificationCenter.default().addObserver(
            forName: .init("com.reorx.gaplesspaste.debug.transfer"), object: nil, queue: .main
        ) { [weak appState, weak menuController] notification in
            guard let spec = notification.object as? String,
                  let parts = try? JSONDecoder().decode([String].self, from: Data(spec.utf8)) else { return }
            Task { @MainActor in
                if ["export", "dump", "open-menu", "key", "appearance", "reduce-motion"].contains(parts.first) {
                    menuController?.debugTransfer(parts)
                } else {
                    appState?.debugTransfer(parts)
                }
            }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.reorx.gaplesspaste.debug.capture"),
            object: nil,
            queue: .main
        ) { notification in
            guard let dir = notification.object as? String else { return }
            Task { @MainActor in captureWindows(to: dir) }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.reorx.gaplesspaste.debug.preview"),
            object: nil,
            queue: .main
        ) { [weak appState] notification in
            guard let spec = notification.object as? String else { return }
            Task { @MainActor in
                guard let appState else { return }
                openPreview(spec, appState: appState)
            }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.reorx.gaplesspaste.debug.preview-action"),
            object: nil,
            queue: .main
        ) { [weak appState] notification in
            guard let command = notification.object as? String else { return }
            Task { @MainActor in appState?.latestPreviewController?.debugPerform(command) }
        }
    }

    private static func openPreview(_ spec: String, appState: AppState) {
        let parts = spec.split(separator: "|", maxSplits: 1)
        guard parts.count == 2,
              case .success(let config) = appState.configStore.lastResult,
              let machine = config.machines.first(where: { $0.name == String(parts[0]) })
        else { return }
        appState.openPreviewWindow(machine: machine, path: String(parts[1]))
    }

    private static func captureWindows(to dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for (index, window) in NSApp.windows.enumerated() where window.isVisible {
            // contentView 的 superview 是 theme frame，连标题栏一起截
            guard let frameView = window.contentView?.superview,
                  let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds)
            else { continue }
            frameView.cacheDisplay(in: frameView.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { continue }
            let title = window.title.isEmpty ? "untitled" : window.title.replacingOccurrences(of: "/", with: "-")
            let url = URL(fileURLWithPath: dir).appendingPathComponent("window-\(index)-\(title).png")
            try? png.write(to: url)
        }
    }
}
#endif
