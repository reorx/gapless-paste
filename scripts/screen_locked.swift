// UI 自动化验收前置检查：打印当前 GUI 会话是否处于锁定状态（locked / unlocked）。
// 读的是 CGSSessionScreenIsLocked。这个标志在屏幕熄灭时也会置位（即使系统已关掉锁屏、
// 唤醒不需要密码），所以 locked 有两种可能：熄屏，或真锁屏。先跑 wake-screen 再跑本脚本，
// 仍是 locked 才是真锁屏。
// locked 期间 AX 读不到 app 窗口（count 为 0）、键盘鼠标事件到不了 app、前台 app 显示为
// loginwindow，所有 AX/按键类验收都会假失败；自截图钩子和 lsappinfo 不受影响。
// 用法：swift scripts/screen_locked.swift
import CoreGraphics

let session = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
let locked = (session["CGSSessionScreenIsLocked"] as? Bool) ?? false
print(locked ? "locked" : "unlocked")
