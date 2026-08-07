-- UI 自动化验收：展开状态栏菜单，点击第 N 个标题匹配的菜单项（同名项每台机器各一个，用序号区分）。
-- 已知局限：个别菜单项（尤其会拉起模态弹窗的）click 会静默失效——菜单不收、action 不触发。
-- 这类入口别硬磕 AX，走 DEBUG 分布式通知钩子（见 scripts/preview_open.swift、App/DebugHooks.swift）。
-- 用法：osascript scripts/menu_click.applescript <菜单项标题> <第几个(1-based)>
on run argv
    set targetTitle to item 1 of argv
    set targetIndex to (item 2 of argv) as integer
    tell application "System Events"
        tell process "GaplessPaste"
            set frontmost to true
            click menu bar item 1 of menu bar 2
            delay 0.5
            set hit to 0
            repeat with mi in (every menu item of menu 1 of menu bar item 1 of menu bar 2)
                if (name of mi) as string is equal to targetTitle then
                    set hit to hit + 1
                    if hit is targetIndex then
                        click mi
                        return "clicked " & targetTitle & " #" & targetIndex
                    end if
                end if
            end repeat
            key code 53
            return "NOT FOUND: " & targetTitle & " #" & targetIndex
        end tell
    end tell
end run
