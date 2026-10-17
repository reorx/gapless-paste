# GaplessPaste

macOS 菜单栏工具：把本机剪贴板里的截图、文件和文本，用最少的步骤传到 SSH 能连上的远端机器，让远端终端里的 Claude Code 立刻用上。

## 为什么需要它

在远端机器上（SSH + tmux）跑 Claude Code 时，本机的截图没法直接粘过去：终端只能传键入的文本，传不了图片。GaplessPaste 按内容类型走两条回传通道：

| 本机剪贴板内容 | GaplessPaste 做什么 | 在远端怎么用 |
| --- | --- | --- |
| 文件（Finder 里 ⌘C） | 按原名上传到远端目录，把远端绝对路径写回本机剪贴板 | 在终端里 ⌘V，把路径粘给 Claude Code |
| 图像（截图、浏览器里拷的图） | 重命名后上传到远端目录，同时把图像写进远端剪贴板 | 在 Claude Code 里 Ctrl+V 直接读图 |
| 图像或文本（剪贴板同步） | 不进目录，直接写进远端剪贴板 | 同上 |

## 功能

- **目录上传**：菜单里按机器列出预设的远端目录，点一下就把剪贴板内容传过去，重名时自动加 `-1`、`-2`
- **快速上传**：给文件和图像各指定一个默认目录，省掉选目录这一步
- **拖拽上传**：把文件拖到菜单栏图标上，在弹出的面板里选目标目录
- **剪贴板双向同步**：把本机剪贴板推到远端，或把远端剪贴板拉回本机
- **预览远端目录**：在独立窗口里浏览远端目录，预览图片、音频和文本，多张图片并排对比，并能把文件复制或下载回本机
- **设置窗口**：用图形界面编辑机器和目录，改动即时校验、自动保存

传输直接调用系统的 `ssh` 和 `scp`，`~/.ssh/config` 里的别名、密钥、agent、跳板都照常可用。连接通过 ControlMaster 复用，连续上传几乎没有等待。

还没有实现的：全局热键、登录时自动启动、从浏览器直接拖图像数据上传。

## 安装

需要 macOS 14 或更新版本，Apple Silicon 与 Intel 通用。

```sh
brew install --cask reorx/tap/gapless-paste
```

Homebrew 7 默认只加载信任过的第三方 tap，提示无法加载 cask 时先运行 `brew trust --tap reorx/tap`。

也可以从 [Releases](https://github.com/reorx/gapless-paste/releases) 下载 dmg，把 GaplessPaste 拖进「应用程序」。发布包经过 Developer ID 签名和 Apple 公证。

## 使用前提

- 远端机器在 `~/.ssh/config` 里有 Host 别名，并且能用 `ssh <别名>` 免密登录（密钥或 agent）。GaplessPaste 以 `BatchMode=yes` 调用 ssh，不会弹出密码输入
- 写入远端剪贴板目前只支持 macOS 远端，而且 SSH 登录的用户要和远端图形界面登录的用户是同一个。远端是 Linux 等其他系统时，同步菜单项置灰，上传图像改为把远端路径写回本机剪贴板

## 配置

首次启动会写入一份示例配置并打开设置窗口。配置文件在 `~/Library/Application Support/GaplessPaste/config.json`：

```json
{
  "machines": [
    {
      "name": "mini",
      "sshAlias": "mini",
      "directories": [
        { "name": "inbox", "path": "~/claude-inbox", "default_of": "FILE" },
        { "name": "screenshots", "path": "~/claude-inbox/screenshots", "default_of": "IMAGE" }
      ]
    }
  ]
}
```

- `sshAlias`：`~/.ssh/config` 里的 Host 名，认证、端口、跳板都交给 ssh config
- `path`：可以用 `~/` 开头，运行时按远端的 `$HOME` 展开
- `default_of`：可选，`FILE` 或 `IMAGE`，把这个目录设为「快速上传」时该类内容的默认落点，每台机器每类最多一个

手改文件后，在菜单里点「重载配置」生效。

日志在 `~/Library/Logs/GaplessPaste/GaplessPaste.log`，每条 ssh / scp 命令的参数、耗时、退出码和 stderr 都记在里面，出问题时先看它。

## 从源码构建

需要 Xcode、[XcodeGen](https://github.com/yonaskolb/XcodeGen) 和 [xcbeautify](https://github.com/cpisciotta/xcbeautify)：

```sh
brew install xcodegen xcbeautify
make dev     # 生成工程、Debug 构建并启动
make test    # 跑 GaplessPasteCore 单测
```

Debug 构建默认用 ad-hoc 签名。要用自己的开发者身份，照 `Config/Local.xcconfig.example` 创建 `Config/Local.xcconfig`。工程约定和其他命令见 [AGENTS.md](AGENTS.md)。

## License

[MIT](LICENSE)
