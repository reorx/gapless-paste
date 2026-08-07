-- UI 自动化验收：打印指定窗口的 AX 树（缩进层级 + 类型 + AXIdentifier + 值），
-- 写任何新 AX 脚本前先用它看清结构，别猜 identifier 和层级。
-- 递归下降，不用 `entire contents`——后者在深层 SwiftUI 树上会静默返回空集合。
-- 用法：osascript scripts/ax_dump.applescript <窗口标题片段> [最大深度，默认 12]
global dumpLines

on run argv
    set windowHint to item 1 of argv
    if (count of argv) ≥ 2 then
        set maxDepth to (item 2 of argv) as integer
    else
        set maxDepth to 12
    end if
    set dumpLines to {}
    tell application "System Events"
        tell process "GaplessPaste"
            set frontmost to true
            delay 0.3
            repeat with w in windows
                if (name of w) contains windowHint then
                    perform action "AXRaise" of w
                    delay 0.2
                    my walk(w, 0, maxDepth)
                    set AppleScript's text item delimiters to linefeed
                    return dumpLines as string
                end if
            end repeat
            return "NOT FOUND window: " & windowHint
        end tell
    end tell
end run

-- 注意：拼接用的变量名别撞 AppleScript 术语——line、outLine（会被解析成 outline）
-- 这类名字赋值直接报 -10003 Access not allowed，故用 buf
on walk(element, depth, maxDepth)
    if depth > maxDepth then return
    tell application "System Events"
        set buf to ""
        repeat depth times
            set buf to buf & "  "
        end repeat
        try
            set buf to buf & ((class of element) as string)
        end try
        try
            set theID to value of attribute "AXIdentifier" of element
            if theID is not "" and theID is not missing value then set buf to buf & " #" & theID
        end try
        try
            set theValue to value of element
            if theValue is not missing value and (theValue as string) is not "" then
                set buf to buf & " = " & (theValue as string)
            end if
        end try
        set end of dumpLines to buf
        try
            repeat with child in UI elements of element
                my walk(child, depth + 1, maxDepth)
            end repeat
        end try
    end tell
end walk
