---
created: 2026-07-07
tags:
  - session
  - macos
  - appkit
  - drag-drop
  - m3
---

# M3 拖拽上传：状态栏图标 drop 检测 + DropPanel

## 概要

实现 spec 触发路径 C（M3）：从 Finder/桌面拖文件到菜单栏图标时，图标下方弹出 DropPanel，把配置里所有「机器 × 目录」平铺成行，每行是独立 drop target，松手即按文件引用模式上传（复用路径 A：清洗文件名 → 探测/mkdir/重名递增/scp → 远端绝对路径写回本地剪贴板 + 通知）。开工前先用 firecrawl 搜索并下载了 Dropzone 4 的官方截图作 UI 参考（面板锚定图标正下方、模糊背景圆角浮层、目标平铺、拖入高亮、drop 后收起），按此形态实现但省略指向箭头与 grid 布局（spec 要求平铺成行）。遵循 BDD：先在 Core 写 `DropTargets` 行为测试再实现，全量 63 个测试绿，`make build` 通过，app 已启动待手工验收。

## 修改的文件

- `GaplessPasteCore/Sources/GaplessPasteCore/DropTargets.swift`（新增）— 纯逻辑：`Config` → 平铺的 `DropTargetRow(machine, directory)`，`label` 为 `机器名/目录名`
- `GaplessPasteCore/Tests/GaplessPasteCoreTests/DropTargetsTests.swift`（新增）— 4 个行为测试：多机器按序平铺、label 格式、无目录机器不产生行、空配置
- `GaplessPaste/UI/DropPanel.swift`（新增）— 三个部件：
  - `StatusItemDropDetector`：贴在 status item button 上的透明覆盖层，注册 `.fileURL` 拖拽；拖入弹面板、拖离延迟 0.7s 隐藏；`mouseDown` 等鼠标事件原样转发给 superview（button），保证点击打开菜单不受影响
  - `DropPanelController`：无边框 `.nonactivatingPanel`（level `.popUpMenu`），锚定图标正下方、水平夹取到屏幕内；drop 后立即收起；全局鼠标按下监听 + `draggingEnded` 兜底收起；配置错误/无目录时显示提示行
  - `DropRowView`：单行独立 drop target，拖入高亮（accent 色 0.3 alpha 圆角），`isBusy` 时拒收
- `GaplessPaste/App/AppState.swift` — 新增 `uploadDroppedFiles(_:machine:directory:)`：过滤 file URL、构造与路径 A 相同的 Payload（`writePathsBackToClipboard: true`）走 `transfer`
- `GaplessPaste/UI/StatusMenuController.swift` — init 时创建 `DropPanelController` 并传入 `statusItem.button`

## 注意事项

- **NSStatusItem 作 drop target 的实现方式**（spec 已知风险 4）：NSStatusBarButton 本身无法直接注册拖拽回调，采用「透明覆盖子视图」方案——`button.addSubview(detector)` + `registerForDraggedTypes([.fileURL])`。关键点是覆盖层会截走鼠标事件，必须把 `mouseDown` / `rightMouseDown` / `otherMouseDown` 原样转发给 superview，否则菜单点不开。此转发依赖 NSStatusBarButton 的事件处理路径，跨 macOS 版本行为待实测验证
- **面板不抢焦点**：`.nonactivatingPanel` + `orderFrontRegardless()`，不成为 key window，不打断用户当前 app；因此点击别处不会自动关闭，需自行加 `NSEvent.addGlobalMonitorForEvents` 鼠标按下监听收起
- **拖离延迟隐藏的状态机**：图标与面板之间有空隙，拖离任一处都 `scheduleHide(0.7s)`，拖入任一处（含面板非行区域，由背景 `NSVisualEffectView` 注册拖拽感知）都 `cancelScheduledHide`；从背景移入行会触发「背景 exited → 行 entered」序列，靠 cancel 及时消掉刚排的 timer
- **drop 只落在行上**：图标覆盖层与面板背景的 `prepareForDragOperation` 返回 `false`（拖到非行区域松手会滑回），只有 `DropRowView.performDragOperation` 真正收货
- **读拖拽文件 URL**：`draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]`；探测用 `canReadObject(forClasses:options:)`
- SourceKit 对新建 Core 文件报 "Cannot find / No such module" 是索引滞后，以 `swift test` / `make build` 为准
- 手工验收清单：拖文件到图标面板出现；丢到目录行上传成功、⌘V 得绝对路径；多文件一次拖拽多行路径;拖离 0.7s 面板消失、拖回保持；点击图标菜单仍正常（重点）；拖拽中 Esc 取消后面板不残留
