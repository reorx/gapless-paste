-- UI 自动化验收：在指定窗口里按 AXIdentifier 找按钮并按下。
-- 优先 perform action "AXPress"（click 按坐标，布局动过后会点偏），失败回退 click。
-- 递归下降查找，不用 `entire contents`——后者在深层 SwiftUI 树上会静默返回空集合。
-- 用法：osascript scripts/ax_press.applescript <窗口标题片段> <AXIdentifier>
--   窗口标题片段示例：设置窗口用 "设置"，预览窗口用 "🔍"
on run argv
    set windowHint to item 1 of argv
    set targetID to item 2 of argv
    tell application "System Events"
        tell process "GaplessPaste"
            set frontmost to true
            delay 0.3
            repeat with w in windows
                if (name of w) contains windowHint then
                    perform action "AXRaise" of w
                    delay 0.2
                    set target to my findButton(w, targetID)
                    if target is missing value then return "NOT FOUND button: " & targetID
                    try
                        perform action "AXPress" of target
                    on error
                        click target
                    end try
                    return "pressed " & targetID
                end if
            end repeat
            return "NOT FOUND window: " & windowHint
        end tell
    end tell
end run

on findButton(element, targetID)
    tell application "System Events"
        try
            if class of element is button and (value of attribute "AXIdentifier" of element) is targetID then
                return element
            end if
        end try
        try
            repeat with child in UI elements of element
                set hit to my findButton(child, targetID)
                if hit is not missing value then return hit
            end repeat
        end try
    end tell
    return missing value
end findButton
