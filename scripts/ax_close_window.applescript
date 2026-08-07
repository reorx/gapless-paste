-- UI 自动化验收：关闭标题匹配的窗口（点标题栏关闭按钮），用于收尾还原现场。
-- 用法：osascript scripts/ax_close_window.applescript <窗口标题片段>
on run argv
    set windowHint to item 1 of argv
    tell application "System Events"
        tell process "GaplessPaste"
            set frontmost to true
            delay 0.3
            repeat with w in windows
                if (name of w) contains windowHint then
                    click (first button of w whose subrole is "AXCloseButton")
                    return "closed " & windowHint
                end if
            end repeat
            return "NOT FOUND window: " & windowHint
        end tell
    end tell
end run
