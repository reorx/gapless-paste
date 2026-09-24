-- UI 自动化验收：点击 Dock 里的 GaplessPaste 图标（模拟用户点 Dock）。
-- Dock 中没有该项时返回 "absent"——也可用来判断 Dock 图标是否显示。
-- 用法：osascript scripts/dock_click.applescript [check]
--   传 check 只检查不点击，返回 "present" / "absent"
on run argv
    set checkOnly to (count of argv) > 0 and item 1 of argv is "check"
    tell application "System Events"
        tell process "Dock"
            repeat with dockItem in UI elements of list 1
                if name of dockItem is "GaplessPaste" then
                    if checkOnly then return "present"
                    click dockItem
                    return "clicked"
                end if
            end repeat
        end tell
    end tell
    return "absent"
end run
