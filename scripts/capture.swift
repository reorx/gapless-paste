// UI 自动化验收：向 GaplessPaste（DEBUG 构建）发分布式通知，让 app 自截图到指定目录。
// app 用 NSView.cacheDisplay 截自己的窗口，不需要 Screen Recording 授权（screencapture 在本机被 TCC 拒绝）。
// 用法：swift scripts/capture.swift <输出目录>
import Foundation

guard CommandLine.arguments.count >= 2 else {
    fputs("usage: swift capture.swift <output-dir>\n", stderr)
    exit(1)
}
// 相对路径按本脚本的 cwd 转绝对路径：app 由 open 启动，cwd 是 /，直接传相对路径会落到 /tmp 等意外位置
let dir = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL.path
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("com.reorx.gaplesspaste.debug.capture"),
    object: dir,
    userInfo: nil,
    deliverImmediately: true
)
// 通知投递是异步的，给接收端一点时间
Thread.sleep(forTimeInterval: 0.8)
