import AppKit
import GaplessPasteCore

// 菜单栏图标与菜单。每次打开时经 menuNeedsUpdate 全量重建，
// 状态（isBusy / 上次结果 / 配置错误）即时反映。

@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let appState: AppState
    private var dropPanelController: DropPanelController!

    /// 菜单项 representedObject 载体（machine × directory）
    private final class UploadTarget: NSObject {
        let machine: Machine
        let directory: RemoteDirectory
        init(machine: Machine, directory: RemoteDirectory) {
            self.machine = machine
            self.directory = directory
        }
    }

    init(appState: AppState) {
        self.appState = appState
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        statusItem.button?.image = NSImage(
            systemSymbolName: "arrow.up.doc.on.clipboard",
            accessibilityDescription: "GaplessPaste"
        )
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        // M3：图标 drop 检测 + 拖拽目标面板
        dropPanelController = DropPanelController(appState: appState, statusButton: statusItem.button)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild(menu)
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()

        // 状态行：进行中/上次结果（禁用项）；上次结果下附相对时间
        // （菜单每次打开经 menuNeedsUpdate 重建，时间随开随算，无需定时刷新）
        if let status = appState.statusLine {
            menu.addItem(disabledItem(status))
            if status.hasPrefix("上次"), let finishedAt = appState.lastFinishedAt {
                menu.addItem(disabledItem("　\(DisplayFormatter.relativeTimeText(from: finishedAt))", small: true))
            }
        }

        let copyItem = actionItem("拷贝上次上传的远端路径", #selector(copyLastPaths))
        copyItem.isEnabled = !appState.lastRemotePaths.isEmpty
        menu.addItem(copyItem)

        if appState.hasRetryableFailure {
            let retryItem = actionItem("重试上次操作", #selector(retryLast))
            retryItem.isEnabled = !appState.isBusy
            menu.addItem(retryItem)
        }

        menu.addItem(.separator())

        switch appState.configStore.lastResult {
        case .failure(let error):
            menu.addItem(disabledItem("⚠️ 配置错误：\(error.localizedDescription)"))
        case .success(let config) where config.machines.isEmpty:
            menu.addItem(disabledItem("还没有机器，去「设置…」添加"))
        case .success(let config):
            for machine in config.machines {
                menu.addItem(NSMenuItem.sectionHeader(title: machine.name))
                // 每台机器区前两项：双向同步剪贴板（推送 / 拉取）。已探测为非 Darwin 时
                // 禁用（降级语义不成立），未探测时保持可用（点击时探测，非 Darwin 则提示
                // 并在下次打开菜单置灰）
                let knownDarwin = appState.remoteIsDarwinIfKnown(machine: machine)
                if knownDarwin == false {
                    menu.addItem(disabledItem("同步到远端剪贴板 →（远端非 macOS）"))
                    menu.addItem(disabledItem("从远端剪贴板同步 ←（远端非 macOS）"))
                } else {
                    let pushItem = actionItem("同步到远端剪贴板 →", #selector(syncClipboard(_:)))
                    pushItem.representedObject = machine
                    pushItem.isEnabled = !appState.isBusy
                    menu.addItem(pushItem)
                    let pullItem = actionItem("从远端剪贴板同步 ←", #selector(syncClipboardFromRemote(_:)))
                    pullItem.representedObject = machine
                    pullItem.isEnabled = !appState.isBusy
                    menu.addItem(pullItem)
                }
                // 预览远端目录：独立于上传管线（不受 isBusy 限制），窗口可多开
                let previewItem = actionItem("🔍 预览远端目录…", #selector(previewFolder(_:)))
                previewItem.representedObject = machine
                menu.addItem(previewItem)
                // M4：快速上传——按剪贴板类型直传该机器的默认目录，跳过选目录。
                // 仅当机器配了至少一个默认目录（文件/图像）时才出现
                if machine.defaultDirectory(for: .file) != nil || machine.defaultDirectory(for: .image) != nil {
                    let quickItem = actionItem("⚡ 快速上传", #selector(quickUpload(_:)))
                    quickItem.representedObject = machine
                    quickItem.isEnabled = !appState.isBusy
                    menu.addItem(quickItem)
                }
                for directory in machine.directories {
                    let item = actionItem("📁 \(directory.name)", #selector(uploadToTarget(_:)))
                    item.representedObject = UploadTarget(machine: machine, directory: directory)
                    item.isEnabled = !appState.isBusy
                    menu.addItem(item)
                }
            }
        }

        menu.addItem(.separator())
        let settingsItem = actionItem("设置…", #selector(openSettings))
        settingsItem.keyEquivalent = ","
        menu.addItem(settingsItem)
        menu.addItem(actionItem("重载配置", #selector(reloadConfig)))
        menu.addItem(actionItem("打开日志", #selector(openLog)))
        let quitItem = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
    }

    private func disabledItem(_ title: String, small: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        if small {
            item.attributedTitle = NSAttributedString(
                string: title,
                attributes: [.font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)]
            )
        }
        return item
    }

    private func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    // MARK: - Actions

    @objc private func uploadToTarget(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? UploadTarget else { return }
        appState.upload(machine: target.machine, directory: target.directory)
    }

    @objc private func syncClipboard(_ sender: NSMenuItem) {
        guard let machine = sender.representedObject as? Machine else { return }
        appState.syncClipboard(machine: machine)
    }

    @objc private func syncClipboardFromRemote(_ sender: NSMenuItem) {
        guard let machine = sender.representedObject as? Machine else { return }
        appState.syncClipboardFromRemote(machine: machine)
    }

    @objc private func previewFolder(_ sender: NSMenuItem) {
        guard let machine = sender.representedObject as? Machine else { return }
        appState.previewFolder(machine: machine)
    }

    @objc private func quickUpload(_ sender: NSMenuItem) {
        guard let machine = sender.representedObject as? Machine else { return }
        appState.quickUpload(machine: machine)
    }

    @objc private func copyLastPaths() {
        appState.copyLastRemotePaths()
    }

    @objc private func retryLast() {
        appState.retryLastOperation()
    }

    @objc private func openSettings() {
        appState.openSettings()
    }

    @objc private func openLog() {
        appState.openLog()
    }

    @objc private func reloadConfig() {
        appState.reloadConfig()
    }
}
