// UI 自动化验收：向 GaplessPaste（DEBUG 构建）发分布式通知，驱动最近打开的预览窗口
// （锁屏等 AX 不可用时的兜底；真实按钮/快捷键/双击手势仍需解锁后走 AX 验）。
// 指令：up | enter|<绝对路径> | select|<绝对路径>[|<绝对路径>…] | refresh | dump
// dump 把窗口状态（根、选中、根下子项展开情况、顶栏提示）写进日志，grep「DEBUG 预览状态」核对。
// 用法：swift scripts/preview_action.swift '<指令>'
import Foundation

guard CommandLine.arguments.count >= 2 else {
    fputs("usage: swift preview_action.swift '<up|enter|path|select|path...|refresh|dump>'\n", stderr)
    exit(1)
}
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("com.reorx.gaplesspaste.debug.preview-action"),
    object: CommandLine.arguments[1],
    userInfo: nil,
    deliverImmediately: true
)
// 通知投递是异步的，给接收端一点时间
Thread.sleep(forTimeInterval: 0.8)
