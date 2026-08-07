// 自动化验收辅助：向 GaplessPaste（DEBUG 构建）发分布式通知，直接打开预览窗口
// （绕过模态路径弹窗——AX 驱动 NSAlert 不可靠）。
// 用法：swift tmp/preview_open.swift <机器名> <远端路径>
import Foundation

guard CommandLine.arguments.count >= 3 else {
    fputs("usage: swift preview_open.swift <machine-name> <remote-path>\n", stderr)
    exit(1)
}
let machine = CommandLine.arguments[1]
let path = CommandLine.arguments[2]
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("com.reorx.gaplesspaste.debug.preview"),
    object: "\(machine)|\(path)",
    userInfo: nil,
    deliverImmediately: true
)
// 通知投递是异步的，给接收端一点时间
Thread.sleep(forTimeInterval: 0.8)
