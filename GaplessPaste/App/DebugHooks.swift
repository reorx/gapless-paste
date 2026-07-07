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

@MainActor
enum DebugHooks {
    static func install() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.reorx.gaplesspaste.debug.capture"),
            object: nil,
            queue: .main
        ) { notification in
            guard let dir = notification.object as? String else { return }
            Task { @MainActor in captureWindows(to: dir) }
        }
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
