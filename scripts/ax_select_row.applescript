-- UI 自动化验收：在指定窗口的 SwiftUI List 里按行文本选中一行（如预览窗口左侧目录树的文件）。
-- 用 set selected of row to true —— 对行内 static text 发 AXPress 无效。
-- 递归下降查找，不用 `entire contents`——后者在深层 SwiftUI 树上会静默返回空集合。
-- 用法：osascript scripts/ax_select_row.applescript <窗口标题片段> <行文本>
on run argv
    set windowHint to item 1 of argv
    set rowText to item 2 of argv
    tell application "System Events"
        tell process "GaplessPaste"
            set frontmost to true
            delay 0.3
            repeat with w in windows
                if (name of w) contains windowHint then
                    perform action "AXRaise" of w
                    delay 0.2
                    set target to my findRow(w, rowText)
                    if target is missing value then return "NOT FOUND row: " & rowText
                    set selected of target to true
                    return "selected " & rowText
                end if
            end repeat
            return "NOT FOUND window: " & windowHint
        end tell
    end tell
end run

on findRow(element, rowText)
    tell application "System Events"
        try
            if class of element is row then
                if my rowMatches(element, rowText) then return element
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
on rowMatches(element, rowText)
    tell application "System Events"
        try
            if class of element is static text and (value of element) is rowText then return true
        end try
        try
            repeat with child in UI elements of element
                if my rowMatches(child, rowText) then return true
            end repeat
        end try
    end tell
    return false
end rowMatches
