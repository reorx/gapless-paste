-- UI 自动化验收：向指定窗口的文本框填值（走剪贴板 ⌘A+⌘V，绕开中文 IME 吞 keystroke）。
-- 同一 AXIdentifier 可能有多个（如每台机器一个名称框），用序号指定第几个（按 AX 树顺序）。
-- 递归下降查找，不用 `entire contents`——后者在深层 SwiftUI 树上会静默返回空集合。
-- 注意：本脚本会覆盖剪贴板，调用方负责先 pbpaste 备份、结束后恢复。
-- 用法：osascript scripts/ax_fill.applescript <窗口标题片段> <AXIdentifier> <第几个(1-based)> <文本>
global matchCount

on run argv
    set windowHint to item 1 of argv
    set targetID to item 2 of argv
    set targetIndex to (item 3 of argv) as integer
    set targetText to item 4 of argv
    set the clipboard to targetText
    set matchCount to 0
    tell application "System Events"
        tell process "GaplessPaste"
            set frontmost to true
            delay 0.3
            repeat with w in windows
                if (name of w) contains windowHint then
                    perform action "AXRaise" of w
                    delay 0.2
                    set target to my findField(w, targetID, targetIndex)
                    if target is missing value then
                        return "NOT FOUND field: " & targetID & " #" & targetIndex
                    end if
                    -- 必须发真实键盘事件：set value of text field 只改显示、不触发 SwiftUI binding
                    set focused of target to true
                    delay 0.2
                    keystroke "a" using command down
                    delay 0.1
                    keystroke "v" using command down
                    delay 0.2
                    return "filled " & targetID & " #" & targetIndex
                end if
            end repeat
            return "NOT FOUND window: " & windowHint
        end tell
    end tell
end run

on findField(element, targetID, targetIndex)
    tell application "System Events"
        try
            if class of element is text field and (value of attribute "AXIdentifier" of element) is targetID then
                set matchCount to matchCount + 1
                if matchCount is targetIndex then return element
            end if
        end try
        try
            repeat with child in UI elements of element
                set hit to my findField(child, targetID, targetIndex)
                if hit is not missing value then return hit
            end repeat
        end try
    end tell
    return missing value
end findField
