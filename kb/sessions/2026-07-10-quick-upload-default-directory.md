---
created: 2026-07-10
tags:
  - quick-upload
  - config
  - directory-role
  - swiftui
  - bdd
---

# 快速上传：目录默认角色 default_of + 「⚡ 快速上传」菜单项

## 概要

起点是用户问「预设的 inbox 与 screenshots 两个上传目录有什么区别」——排查后确认二者在程序逻辑上**完全等价**，只是首启模板里预设的两条 `RemoteDirectory`（路径不同、语义靠人为约定），代码无任何按 name 的分支。由此引出新需求：给目录加一个 `default_of` 属性（`null` / `FILE` / `IMAGE`），标记它作为「文件上传」还是「图片上传」的默认落点，为「不选目录直接上传」的入口铺路。

先用 `AskUserQuestion` 敲定两个会左右数据模型与校验的决策：**（1）本次连带实现「快速上传」消费入口**（否则属性无可观测行为）；**（2）唯一性作用域=每台机器内**（每机器最多一个 FILE + 一个 IMAGE，跨机器互不影响，不预设单机器）；外加一个 UI 决策：快速上传遇到图像**仍保留重命名浮窗**（一致性优先）。随后按 BDD 先在 Core 写 12 条行为测试再实现，App 层加 `quickUpload` 与条件显示的菜单项，设置窗口每个目录行加角色下拉。`swift test` 77 全绿、`make build` 通过。端到端真机（菜单点击→远端上传）本次未验证，需远端环境。

## 修改的文件

- `GaplessPasteCore/Sources/GaplessPasteCore/ConfigModel.swift` — 新增 `DirectoryRole` 枚举（`.file`/`.image` ↔ `"FILE"`/`"IMAGE"`）；`RemoteDirectory` 加 `defaultOf: DirectoryRole?` + 自定义 `CodingKeys`（映射 `default_of`）；`Machine.defaultDirectory(for:)` 辅助；`Config.validate()` 加每机器内唯一校验 + `ConfigError.duplicateDefaultDirectory`；模板给 `inbox` 标 FILE、`screenshots` 标 IMAGE，`_readme` 补 `default_of` 说明
- `GaplessPasteCore/Tests/GaplessPasteCoreTests/ConfigModelTests.swift` — 新增「默认目录角色 default_of」suite：解析 FILE/IMAGE、缺省为 nil、非法值抛错、同机器重复 FILE/IMAGE 校验失败、FILE+IMAGE 共存合法、跨机器不冲突、`defaultDirectory(for:)`、序列化往返 + 普通目录不写该键、模板角色（BDD 先行）
- `GaplessPaste/App/AppState.swift` — 新增 `quickUpload(machine:)`：读剪贴板分类 → 文件引用走 `.file` 默认目录、图像走 `.image` 默认目录 → 委托现有 `upload()`；纯文本引导去「同步剪贴板」、空剪贴板与未配默认目录均通知提示
- `GaplessPaste/UI/StatusMenuController.swift` — 每台机器区加「⚡ 快速上传」项（`quickUpload(_:)` action），**仅当该机器配了至少一个默认目录时出现**，`isBusy` 时禁用
- `GaplessPaste/UI/SettingsWindow.swift` — `EditableDirectory` 加 `defaultOf`；load/buildConfig 双向映射；目录行加 `Picker`（普通 / 文件默认 / 图像默认，`accessibilityIdentifier("directory-default-of")`），name 字段宽 130→120 腾位
- `AGENTS.md` — 进度加「快速上传」；配置段补 `default_of` 语义与菜单项
- `kb/sessions/2026-07-10-quick-upload-default-directory.md` — 本文件

## 注意事项

- **`default_of` 唯一性作用域是「每台机器内」**，不是全局：`validate()` 对每台机器各自维护一个 `Set<DirectoryRole>`，重复即抛 `duplicateDefaultDirectory`。选它是因为不预设「只有一台机器」；代价是快速上传仍需知道是哪台机器（故入口挂在每台机器的菜单区，而非一个全局热键 + 「默认机器」概念）。
- **Codable 处理**：`defaultOf` 是 Optional，靠自定义 `CodingKeys`（`case defaultOf = "default_of"`）+ 合成 Codable 即可——解码缺省为 `nil`，编码 `nil` 自动省略该键，所以**普通目录不写 `default_of`**，且与既有 `sortedKeys`/`withoutEscapingSlashes` 编码兼容。`DirectoryRole` 用 `String` raw enum，非法值（如 `"VIDEO"`、小写 `"file"`）直接解码抛错——严格匹配，配置写错即报错。
- **快速上传复用最大化**：`quickUpload` 只负责「按剪贴板类型选对目录」，选完直接委托 `upload(machine:directory:)`，重命名浮窗、重名探测（`test -e` + `-1/-2`）、远端剪贴板注入全部继承现有路径 A，不重复实现。代价是剪贴板被读两次（quickUpload 分类一次、upload 内部再分类一次）——毫秒间隔用户不会改剪贴板，可接受；日志会打两条分类便于排查。
- **菜单项条件显示**：仅当 `defaultDirectory(for:.file) != nil || …(.image) != nil` 才加「⚡ 快速上传」，避免出现一个点了只会弹「未配置默认目录」的死项。默认模板（inbox=FILE、screenshots=IMAGE）会显示，用户新建的空机器不显示。
- **向后兼容**：缺省 `default_of` = 普通目录。旧 `config.json`（无该键）照常解析，只是不会出现快速上传项——需去「设置…」给目录选角色，或手动加 `default_of` 才启用。
- **验证边界**：本次只到 Core 单测全绿 + app 编译通过，**未做真机 UI 自动化验收**（对比 M4 settings 那次做了 AX 操作 + 自截图取证）。Picker 的 SwiftUI Optional 绑定（`DirectoryRole?.none` / `.some(...)` 精确 tag）是唯一中风险点，端到端与之一并留待真机验。
