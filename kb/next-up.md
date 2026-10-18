# Next up

## 下一个正式版（v0.2.0 之后的第一个 tag）发布后

- 在装着 v0.2.0（brew 或 dmg 安装）的机器上确认 Sparkle 自己弹出更新提示并能装上。v0.2.0 的验收是本地 0.1.9 手动点「检查更新…」更新上来的，还没经历过一次真实的每日自动检查。结果写进 `kb/docs/release.md` 的 Sparkle 一节，然后删掉本条
- 确认 tap 里 cask 的 `version` 跟上了，且 `brew upgrade` 不会和 Sparkle 抢（cask 有 `auto_updates true`，普通 `brew upgrade` 应跳过它，`--greedy` 才升级）
