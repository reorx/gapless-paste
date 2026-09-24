-- UI 自动化验收：打印 GaplessPaste 当前获得焦点的窗口标题（AXFocusedWindow），
-- 以及 app 是否在前台，用于核对 ⌘` 切窗 / Dock 点击后焦点落点。
-- 输出形如 "frontmost=true focused=🔍 机器 : /路径"；无焦点窗口时 focused=<none>
-- 用法：osascript scripts/ax_focused_window.applescript
tell application "System Events"
    tell process "GaplessPaste"
        set isFront to frontmost
        try
            set focusedTitle to name of (value of attribute "AXFocusedWindow")
        on error
            set focusedTitle to "<none>"
        end try
        return "frontmost=" & isFront & " focused=" & focusedTitle
    end tell
end tell
