// UI 自动化验收：向 GaplessPaste（DEBUG 构建）发分布式通知，让 app 自截图到指定目录。
// app 用 NSView.cacheDisplay 截自己的窗口，不需要 Screen Recording 授权（screencapture 在本机被 TCC 拒绝）。
// 用法：swift scripts/capture.swift <输出目录>
import Foundation

guard CommandLine.arguments.count >= 2 else {
    fputs("usage: swift capture.swift <output-dir>\n", stderr)
    exit(1)
}
let dir = CommandLine.arguments[1]
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("com.reorx.gaplesspaste.debug.capture"),
    object: dir,
    userInfo: nil,
    deliverImmediately: true
)
// 通知投递是异步的，给接收端一点时间
Thread.sleep(forTimeInterval: 0.8)
