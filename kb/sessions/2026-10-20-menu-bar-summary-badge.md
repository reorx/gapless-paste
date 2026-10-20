---
created: 2026-10-20
tags:
  - menu-bar
  - status-feedback
  - clipboard
  - dock
  - acceptance
---

# 实现传输摘要、右下角状态徽标与详情窗口，并收窄菜单和验证 Dock 生命周期

## 概要

按已确认的 C 摘要＋③右下角徽标计划，在当前 master 与原 checkout 完成实现。顶部不再直接显示长文件名和错误正文，而是两行结果、类型／数量、方向与相对时间；完整信息进入原生详情窗口。菜单关闭时仍即时显示 ↑／↓／✓／!，成功约两秒恢复待机，失败在查看详情或新操作后解除提醒。传输记录与反馈分离，旧超时不能覆盖新任务。

用户已手工验收整体效果，反馈「应该没什么问题」，追加要求菜单更窄、无窗口时不显示 Dock。菜单从最初的 320 pt 收窄到 288 pt；预览、设置、详情共用窗口追踪，关闭最后一个普通窗口回到 accessory 并从 Dock 隐藏。真机回归复现系统拒绝转换导致 Dock 遗留，随后修复并以实际 Dock 项和 activation policy 验证。

## 修改的文件

- `GaplessPasteCore/Sources/GaplessPasteCore/TransferPresentation.swift`、对应 `TransferPresentationTests.swift`：纯 Swift 元数据、最近记录、独立徽标反馈与按 ID 校验的状态转换；8 个行为测试先红后绿。
- `GaplessPaste/App/AppState.swift`：统一展示状态入口，接通普通／快速／拖拽上传与双向同步；成功计时、取消／拒绝、失败确认、详情快照；图像上传后注入失败统一处理为部分成功，保留路径且无重新上传。
- `GaplessPaste/UI/StatusMenuController.swift`、`TransferSummaryView.swift`：保留 NSStatusItem／NSMenu，固定 288 pt 摘要、按实际宽度省略机器名、标准详情菜单项；传输中安全刷新已有菜单项，不重建 tracking 菜单。
- `GaplessPaste/UI/StatusBadgeRenderer.swift`：18 pt template 图标，主图标位置不变，右下角叠加无托盘箭头／勾／叹号；300 ms 后只让徽标轻微改变透明度，支持减少动态效果。
- `GaplessPaste/UI/TransferDetailsWindow.swift`：可调整大小、选择文本、换行与滚动的原生详情，显示完整文件名／元数据／错误，使用稳定值快照。
- `GaplessPaste/App/DockPresence.swift`：详情接入 `track`，最后关闭后等待 100 ms 再转换；检查系统返回值，转换被拒时退出激活状态后有限重试，新窗口打开时取消待隐藏操作。DEBUG 保存最近 40 条转换记录及关窗接口。
- `GaplessPaste/App/DebugHooks.swift`、`GaplessPasteApp.swift`、`scripts/transfer_debug.swift`：仅 DEBUG 的状态夹具、真实业务入口、图标导出、原生菜单、事件队列按键、动画与外观覆盖、窗口诊断。
- `scripts/test_dock_presence.py`、`Makefile`：新增 `make test-dock` 真机回归，直接检查 Dock 项与 activation policy。
- `README.md`、`AGENTS.md`、功能与 UI 验收文档、计划、known issues：同步最终行为与验收边界；Mockup、测试夹具和截图均留在忽略的 `tmp/`，未加入版本控制。

## 验证结果

| 检查 | 结果 |
| --- | --- |
| BDD | 实现前新增测试因缺少展示类型失败；实现后修正 300 ms 的 Date 浮点边界，确定性推进时间，无 Core sleep |
| `make test` | 157 tests / 19 suites 通过，含新增 8 个展示行为测试 |
| `make build` | Debug 构建通过，新增源文件由 xcodegen 自动纳入；没有手改生成工程 |
| `make test-release` | appcast、非法构建号、cask auto_updates、嵌套代码签名检查通过 |
| `make test-dock` | 无窗口时 absent／accessory；仅详情或仅设置时 present／regular；真实标题栏关闭最后详情后 absent；混合窗口逐个关闭、设置仍在时 present，最后设置关闭后 absent |
| Dock TDD | 原实现曾失败：追踪窗口已空，但转换返回 false、activation policy 随后回滚 regular，实际 Dock 仍在；保留失败日志，修复后以同一真机回归验证 |
| Dock 延迟取消 | 关闭最后详情并在 20 ms 后重开设置，等待后 Dock 仍在且仅设置被追踪；最后关闭设置后 Dock 消失 |
| localhost 真实传输 | 普通多文件、快速上传、drop 业务入口、文本／图像推送和拉取均通过；核对远端实际文件字节、路径、重名结果和元数据 |
| 拒绝、失败与部分成功 | 空本地／空远端不造成功且无 busy 悬挂；失败保留合法重试；真实上传后分别模拟注入非零退出／异常，保留可读路径，调用重试不新增重复文件 |
| 原生摘要与详情 | 288 pt、长机器名省略、类型数量和时间保留；长文件名与错误可读取／滚动，文本正文不进入展示模型；查看失败详情解除提醒，新传输不覆盖旧详情 |
| 原生菜单键盘导航 | 由 app 事件队列投递 Down／Down／Return，标准详情菜单项出现真实蓝色选中态并打开详情，AX 树与失败确认通过；与系统级／物理按键区分 |
| 徽标与外观 | 真实 2× 菜单栏与菜单深浅外观截图；全部 5 种状态导出深浅 1×／2×；箭头无托盘；进行中忙碌项置灰而预览仍可用 |
| 动画与时序 | Core 验成功两秒清徽标、旧事件隔离、300 ms 启动与 reduce motion；原生 DEBUG 分支验证 reduce motion 静态箭头、停止循环；状态按钮 AX 描述包含方向与结果 |
| 数据恢复 | 未改真实 config，最终与备份 cmp 一致；真实传输脚本 finally 按 item/type 原始 Data 恢复完整剪贴板并核对相等 |
| 资源收尾 | 关闭验收窗口、清空 DEBUG 夹具、恢复 app／系统外观和减少动态效果覆盖，恢复 Thaw；本次保活进程已结束，`mac-dev-cleanup --only browser --min-age 2` 无残留可清理，未启动浏览器或模拟器 |

截图、AX 树与验收脚本／日志归档：`tmp/2026-10-20-menu-bar-summary-badge/`。重点文件：

- `final-narrow-menu.png`：收窄后的原生两行摘要与长机器名。
- `final-system-dark-menu.png`：系统深色外观下的真实菜单栏与菜单；测试结束恢复原系统外观。
- `final-native-keyboard-selected.png`、`final-keyboard-details/`：原生键盘选中态与详情。
- `final-stable-details/`、`real-partial-details/`：稳定失败快照和真实部分成功详情。
- `icons/`：绘制资产；不能当作真实系统菜单栏截图。
- `transfer-acceptance.log`、`native-keyboard.log`、`native-finish.log`、`native-dark.log`、`dock-acceptance.log`：对应验证结果。构建、Core 与发布脚本日志另在 `tmp/menu-bar-*.log`。

## 注意事项

- 最近记录只持有文件名／大小／字数等元数据，不持有文本正文或图像。成功反馈到期、失败确认不删除记录；拒绝操作恢复此前记录。图像上传已落盘后的注入异常不能归入可重新上传的失败。
- 菜单摘要用实际布局压缩机器名，类型数量和时间保留；主菜单无完整错误／长文件名。普通配置动作仍是标准 NSMenuItem，保留现有拖拽覆盖层，不增设徽标命中层。
- 原生详情是值类型快照，可同时打开多次；只有其对应操作仍需提醒时才确认。详情与预览／设置一样参与 Dock 生命周期，全部最小化仍算有窗口。
- `NSApp.setActivationPolicy(.accessory)` 的返回值必须检查：本机在 willClose 后立即 dispatch 转换曾返回 false，属性短暂变为 accessory 后又回滚 regular。修复采用 100 ms 收尾窗口和最多 5 次转换，失败后先 deactivate；新窗口取消待执行任务，始终以窗口集合为空为前提，不持续轮询。
- `open-menu` 在 common run-loop block 中打开，不能在 MainActor Task 内同步嵌套菜单 tracking，否则验收通知会排队，产生“界面没更新”的假象。dump 前删除旧 JSON，避免读到旧状态。
- Thaw 会把 status item 移到屏幕外，AX click 可能只打开其管理栏；本次临时退出，结束恢复。系统级合成按键和 AX 菜单动作曾静默失效，最终以原生事件队列、真实选中截图和详情 AX 树验证导航，不把 DEBUG 直调详情等同于实际菜单导航。
- 不新增配置、队列、持久化历史，不发版、不 push；代码、测试与文档统一提交到 master。Mockup 明确保留本地，不强制添加任何忽略文件。

## 遗留问题

- 本机只有 2× 显示器，1× 仅检查绘制资产；没有独立 1× 实屏验证。
- 减少动态效果覆盖 Core 与 DEBUG 静态分支，未切换真实系统设置验证通知链路。
- drop 的真实上传入口已验证；完整物理拖拽手势未自动重演，原有 drop 交互层未改动。系统级合成键盘仍有工具限制，原生菜单队列导航已通过。
- 原有 Dock 切窗、最小化恢复、主菜单等未验项保留在 known issues，本次不扩展范围。

## 已解决的已知问题

- 窗口全部关闭后 Dock 偶发遗留：在真机回归中复现系统拒绝 accessory 转换，补充收尾等待和有限重试，并验证实际 Dock 图标消失；失败证据为 `dock-instrumented.log` 与 `dock-transitions.json`。
- Dock 形态的“最后预览关闭但设置仍在／最后设置关闭／仅设置”未验收子项：新增可重复真机脚本，实际 Dock 与 activation policy 均符合预期；补充仅详情与混合窗口场景。原条目其余未验交互继续保留。

## 相关文档

- [菜单摘要与徽标实施计划](../plans/2026-10-20-menu-bar-summary-and-status-badge.md) — 依据并更新完成结果。
- [功能与行为规则](../docs/features.md) — 更新摘要、详情、反馈、部分成功和 Dock 规则。
- [UI 自动化验收手册](../docs/ui-acceptance.md) — 更新 DEBUG 命令、Dock 回归与验收通道限制。
- [Known Issues](../known-issues.md) — 删除已验收的 Dock 子项，保留范围外未验收交互。
- [菜单设计稿会话](2026-10-20-menu-bar-design-mockup.md) — 参考已确认设计与 Mockup 不入库的约束。
