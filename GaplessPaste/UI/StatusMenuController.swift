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

        // 状态行：进行中/上次结果（禁用项）
        if let status = appState.statusLine {
            menu.addItem(disabledItem(status))
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
            menu.addItem(disabledItem("配置里还没有机器，先打开配置添加"))
        case .success(let config):
            for machine in config.machines {
                menu.addItem(NSMenuItem.sectionHeader(title: machine.name))
                // 每台机器区第一项：同步剪贴板。已探测为非 Darwin 时禁用（降级语义不成立），
                // 未探测时保持可用（点击时探测，非 Darwin 则提示并在下次打开菜单置灰）
                let knownDarwin = appState.remoteIsDarwinIfKnown(machine: machine)
                let syncItem: NSMenuItem
                if knownDarwin == false {
                    syncItem = disabledItem("⇄ 同步剪贴板（远端非 macOS）")
                } else {
                    syncItem = actionItem("⇄ 同步剪贴板", #selector(syncClipboard(_:)))
                    syncItem.representedObject = machine
                    syncItem.isEnabled = !appState.isBusy
                }
                menu.addItem(syncItem)
                for directory in machine.directories {
                    let item = actionItem("📁 \(directory.name)", #selector(uploadToTarget(_:)))
                    item.representedObject = UploadTarget(machine: machine, directory: directory)
                    item.isEnabled = !appState.isBusy
                    menu.addItem(item)
                }
            }
        }

        menu.addItem(.separator())
        menu.addItem(actionItem("打开配置", #selector(openConfig)))
        menu.addItem(actionItem("重载配置", #selector(reloadConfig)))
        menu.addItem(actionItem("打开日志", #selector(openLog)))
        let quitItem = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
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

    @objc private func copyLastPaths() {
        appState.copyLastRemotePaths()
    }

    @objc private func retryLast() {
        appState.retryLastOperation()
    }

    @objc private func openConfig() {
        appState.openConfig()
    }

    @objc private func openLog() {
        appState.openLog()
    }

    @objc private func reloadConfig() {
        appState.reloadConfig()
    }
}
