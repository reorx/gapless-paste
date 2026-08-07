---
created: 2026-08-07
tags:
  - bugfix
  - ssh
  - controlmaster
  - tmp-cleanup
  - tdd
---

# 修复 /tmp 周期清理删掉 ControlPath 目录导致所有 ssh 操作失败的 bug

## 概要

用户报告 8 月 7 日凌晨「从远端剪贴板同步 ←」失败。排查日志发现两次尝试均报 `unix_listener: cannot bind to path /tmp/gaplesspaste-501/<hash>: No such file or directory`（exit 255）。根因：ControlMaster socket 目录 `/tmp/gaplesspaste-501` 只在 `AppState.init` 创建一次，而 macOS 的周期清理（dirhelper 删除 /tmp 下 3 天未访问的条目）在 app 长时间挂机期间（上次成功操作是 7 月 30 日）把空闲目录删掉了，此后所有 ssh/scp 操作（上传、剪贴板双向同步、预览）都会以同样方式失败，直到重启 app。修法：按 TDD 先在 Core 写复现测试，然后给 `SSHCommandBuilder` 增加幂等的 `ensureControlPathDirectory()`（0700），并在 `SSHRunner.run`——所有 ssh/scp 的唯一入口——每次执行前调用重建。真机闭环验证：在目录不存在的情况下启动新构建，AX 驱动菜单触发同一拉取操作，两条 ssh 命令均 exit 0，目录以 `drwx------` 自动重建。

## 修改的文件

- `GaplessPasteCore/Sources/GaplessPasteCore/SSHCommandBuilder.swift` — 新增 `ensureControlPathDirectory(fileManager:)`：幂等创建 socket 目录（0700），带注释说明 /tmp 周期清理背景
- `GaplessPasteCore/Tests/GaplessPasteCoreTests/SSHCommandBuilderTests.swift` — 新增复现测试 `recreatesControlPathDirectoryAfterCleanup`：首次创建 + 权限 0700、模拟清理删除后重建、已存在时幂等不抛错
- `GaplessPaste/Services/SSHRunner.swift` — init 增加 `builder: SSHCommandBuilder` 参数；`run()` 开头每次执行前重建 ControlPath 目录（失败只记日志，让 ssh 自身报错走正常失败路径）
- `GaplessPaste/App/AppState.swift` — 移除启动时的一次性 `createDirectory`（已由 runner 每次执行前保证），`SSHRunner` 构造传入 builder

## 注意事项

- **/tmp 下的长驻目录不能只在启动时创建一次**：macOS dirhelper 会删除 /tmp 下数天未访问的条目，长时间挂机的 menubar app 必须在每次使用前幂等重建。`createDirectory(withIntermediateDirectories: true)` 对已存在目录不报错、不改权限，天然幂等，每次调用开销可忽略
- 修在 `SSHRunner.run` 这个 choke point 而不是各个动作入口，一处覆盖所有 ssh/scp 路径，后续新增功能自动受益
- `unix_listener: cannot bind` 报错发生在 ssh 建连之前（创建复用 socket 阶段），与远端可达性无关——排错时看到它先查 ControlPath 父目录是否存在
- 状态栏菜单的 AX 结构是扁平的：机器名（如 "mini"）是不可点的分组项，动作项直接平铺在顶层菜单，两台机器会出现同名菜单项（如两个「从远端剪贴板同步 ←」），AX 脚本需按索引点击而不能按名字

## 遗留问题

无。

## 相关文档

无涉及 KB 文档。
