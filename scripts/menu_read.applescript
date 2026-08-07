-- UI 自动化验收：展开状态栏菜单并读出全部菜单项标题（不截图即可核对菜单状态），读完 Esc 收起。
-- LSUIElement app 的 status item 路径固定为 menu bar item 1 of menu bar 2。
-- 用法：osascript scripts/menu_read.applescript
tell application "System Events"
    tell process "GaplessPaste"
        set frontmost to true
        click menu bar item 1 of menu bar 2
        delay 0.5
        set titles to name of every menu item of menu 1 of menu bar item 1 of menu bar 2
        key code 53
        return titles
    end tell
end tell
