-- UI 自动化验收：双击指定窗口 SwiftUI List 里某一行的文本（如预览窗口目录树的文件夹 → 进入该目录）。
-- AppleScript 发不出 clickState=2 的双击：按行文本递归找到元素，取其中心坐标，
-- 交给同目录的 mouse_double_click.swift 发真实 CGEvent 双击（会真实移动鼠标，结束后移回原位）。
-- 目标行必须在屏幕上可见、未被其他窗口遮挡；锁屏时无效（先跑 screen_locked.swift）。
-- 递归下降查找，不用 `entire contents`——后者在深层 SwiftUI 树上会静默返回空集合。
-- 用法：osascript scripts/ax_double_click.applescript <窗口标题片段> <行文本>
on run argv
    set windowHint to item 1 of argv
    set rowText to item 2 of argv
    set scriptDir to do shell script "dirname " & quoted form of POSIX path of (path to me)
    set center to missing value
    tell application "System Events"
        tell process "GaplessPaste"
            set frontmost to true
            delay 0.3
            repeat with w in windows
                if (name of w) contains windowHint then
                    perform action "AXRaise" of w
                    delay 0.3
                    set hitRow to my findRow(w, rowText)
                    if hitRow is missing value then return "NOT FOUND row: " & rowText
                    set hitText to my findText(hitRow, rowText)
                    if hitText is missing value then return "NOT FOUND text in row: " & rowText
                    set {px, py} to position of hitText
                    set {sw, sh} to size of hitText
                    set center to {(px + sw / 2) as integer, (py + sh / 2) as integer}
                    exit repeat
                end if
            end repeat
        end tell
    end tell
    if center is missing value then return "NOT FOUND window: " & windowHint
    return do shell script "swift " & quoted form of (scriptDir & "/mouse_double_click.swift") & " " & (item 1 of center) & " " & (item 2 of center)
end run

on findRow(element, rowText)
    tell application "System Events"
        try
            if class of element is row then
                if my findText(element, rowText) is not missing value then return element
            end if
        end try
        try
            repeat with child in UI elements of element
                set hit to my findRow(child, rowText)
                if hit is not missing value then return hit
            end repeat
        end try
    end tell
    return missing value
end findRow

-- 行文本可能嵌在任意深度的 static text 里（Label 图标 + 文字），逐层找
on findText(element, rowText)
    tell application "System Events"
        try
            if class of element is static text and (value of element) is rowText then return element
        end try
        try
            repeat with child in UI elements of element
                set hit to my findText(child, rowText)
                if hit is not missing value then return hit
            end repeat
        end try
    end tell
    return missing value
end findText
