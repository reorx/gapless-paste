// UI 自动化验收：在屏幕坐标 (x, y) 发一次真实的鼠标左键双击（CGEvent）。
// AppleScript 的 click 发不出 clickState=2 的双击，SwiftUI onTapGesture(count: 2) 收不到；
// 这里手动构造两组 down/up，第二组 mouseEventClickState = 2。
// 坐标为全局屏幕坐标（左上角原点，与 AX 的 position 一致）。双击后鼠标移回原位。
// 需要调用方（iTerm2）有 Accessibility 授权，子进程发事件随之生效。
// 用法：swift scripts/mouse_double_click.swift <x> <y>
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count >= 3, let x = Double(args[1]), let y = Double(args[2]) else {
    fputs("usage: swift mouse_double_click.swift <x> <y>\n", stderr)
    exit(1)
}
let point = CGPoint(x: x, y: y)
let source = CGEventSource(stateID: .hidSystemState)
let original = CGEvent(source: nil)?.location

func post(_ type: CGEventType, at location: CGPoint, clickState: Int64 = 0) {
    guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: location, mouseButton: .left) else {
        fputs("failed to create \(type) event\n", stderr)
        exit(1)
    }
    if clickState > 0 {
        event.setIntegerValueField(.mouseEventClickState, value: clickState)
    }
    event.post(tap: .cghidEventTap)
}

post(.mouseMoved, at: point)
usleep(80_000)
for clickState: Int64 in [1, 2] {
    post(.leftMouseDown, at: point, clickState: clickState)
    usleep(30_000)
    post(.leftMouseUp, at: point, clickState: clickState)
    usleep(60_000)
}
if let original {
    usleep(150_000)
    post(.mouseMoved, at: original)
}
print("double-clicked at \(Int(x)),\(Int(y))")
