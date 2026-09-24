// UI 自动化验收前置检查：打印当前 GUI 会话是否锁屏（locked / unlocked）。
// 锁屏时 AX 读不到 app 窗口（count 为 0）、键盘事件到不了 app、前台 app 显示为 loginwindow，
// 所有 AX/按键类验收都会假失败；自截图钩子和 lsappinfo 不受影响。
// 用法：swift scripts/screen_locked.swift
import CoreGraphics

let session = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
let locked = (session["CGSSessionScreenIsLocked"] as? Bool) ?? false
print(locked ? "locked" : "unlocked")
