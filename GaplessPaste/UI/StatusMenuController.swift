import AppKit
import GaplessPasteCore
import Sparkle

// 菜单结构在打开时构建；传输状态变化即时刷新徽标和已有菜单项，不中断菜单 tracking。

@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let appState: AppState
    private let updateController: UpdateController
    private var dropPanelController: DropPanelController!
    private let summaryView = TransferSummaryView()
    private var detailItem: NSMenuItem?
    private var copyItem: NSMenuItem?
    private var retryItem: NSMenuItem?
    private var transferItems: [NSMenuItem] = []
    private var animationDelay: DispatchWorkItem?
    private var animationTimer: Timer?
    private var animatedOperationID: UUID?
    private var animationStartedAt = Date()
    private var accessibilityObserver: NSObjectProtocol?

    #if DEBUG
    private var debugReduceMotion: Bool?
    #endif

    private var reduceMotion: Bool {
        #if DEBUG
        if let debugReduceMotion { return debugReduceMotion }
        #endif
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// 菜单项 representedObject 载体（machine × directory）
    private final class UploadTarget: NSObject {
        let machine: Machine
        let directory: RemoteDirectory
        init(machine: Machine, directory: RemoteDirectory) {
            self.machine = machine
            self.directory = directory
        }
    }

    init(appState: AppState, updateController: UpdateController) {
        self.appState = appState
        self.updateController = updateController
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        statusItem.button?.setAccessibilityIdentifier("gapless-status")
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.minimumWidth = TransferSummaryView.menuWidth
        menu.delegate = self
        statusItem.menu = menu
        // M3：图标 drop 检测 + 拖拽目标面板
        dropPanelController = DropPanelController(appState: appState, statusButton: statusItem.button)
        appState.onPresentationChange = { [weak self] in self?.refreshPresentation() }
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refreshPresentation() } }
        refreshPresentation()
    }

    private func refreshPresentation() {
        let state = appState.presentation
        summaryView.update(state)
        detailItem?.title = state.record?.needsAttention == true ? "查看失败详情…" : "查看传输详情…"
        detailItem?.isEnabled = state.record != nil
        copyItem?.isEnabled = !appState.lastRemotePaths.isEmpty
        retryItem?.isHidden = !appState.hasRetryableFailure
        retryItem?.isEnabled = !appState.isBusy && appState.hasRetryableFailure
        for item in transferItems {
            let machine = item.representedObject as? Machine
            let isSync = item.action == #selector(syncClipboard(_:)) || item.action == #selector(syncClipboardFromRemote(_:))
            item.isEnabled = !appState.isBusy && !(isSync && machine.map { appState.remoteIsDarwinIfKnown(machine: $0) == false } == true)
        }
        let description = "GaplessPaste，" + state.title + "，" + state.subtitle()
        statusItem.button?.setAccessibilityLabel(description)
        statusItem.button?.setAccessibilityHelp(description)
        statusItem.button?.toolTip = description
        statusItem.button?.image = StatusBadgeRenderer.image(feedback: state.feedback)

        if !state.isBusy || reduceMotion || animatedOperationID != state.record?.id {
            stopAnimation()
        }
        guard state.isBusy, !reduceMotion, animationDelay == nil, animationTimer == nil,
              let record = state.record else { return }
        animatedOperationID = record.id
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.appState.presentation.record?.id == record.id,
                  self.appState.isBusy, !self.reduceMotion else { return }
            self.animationDelay = nil
            self.animationStartedAt = Date()
            let timer = Timer(timeInterval: 1.0 / 12, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.animateBadge() }
            }
            self.animationTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        animationDelay = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, 0.3 - Date().timeIntervalSince(record.startedAt)), execute: work)
    }

    private func animateBadge() {
        guard appState.isBusy, !reduceMotion else { stopAnimation(); return }
        let elapsed = Date().timeIntervalSince(animationStartedAt)
        let alpha = 0.8 + 0.2 * cos(elapsed * .pi * 2 / 1.2)
        statusItem.button?.image = StatusBadgeRenderer.image(feedback: appState.presentation.feedback, badgeAlpha: alpha)
    }

    private func stopAnimation() {
        animationDelay?.cancel()
        animationDelay = nil
        animationTimer?.invalidate()
        animationTimer = nil
        animatedOperationID = nil
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild(menu)
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()

        transferItems.removeAll()
        let summary = NSMenuItem()
        summary.isEnabled = false
        summary.view = summaryView
        menu.addItem(summary)
        let details = actionItem("查看传输详情…", #selector(showDetails))
        details.setAccessibilityIdentifier("transfer-details")
        menu.addItem(details)
        detailItem = details
        let copy = actionItem("拷贝上次上传的远端路径", #selector(copyLastPaths))
        menu.addItem(copy)
        copyItem = copy
        let retry = actionItem("重试上次操作", #selector(retryLast))
        menu.addItem(retry)
        retryItem = retry

        menu.addItem(.separator())

        switch appState.configStore.lastResult {
        case .failure(let error):
            menu.addItem(disabledItem("⚠️ 配置错误：\(error.localizedDescription)"))
        case .success(let config) where config.machines.isEmpty:
            menu.addItem(disabledItem("还没有机器，去「设置…」添加"))
        case .success(let config):
            for machine in config.machines {
                menu.addItem(TransferSummaryView.labelItem(machine.name))
                // 每台机器区前两项：双向同步剪贴板（推送 / 拉取）。已探测为非 Darwin 时
                // 禁用（降级语义不成立），未探测时保持可用（点击时探测，非 Darwin 则提示
                // 并在下次打开菜单置灰）
                let knownDarwin = appState.remoteIsDarwinIfKnown(machine: machine)
                let pushItem = actionItem(knownDarwin == false ? "同步到远端剪贴板 →（远端非 macOS）" : "同步到远端剪贴板 →", #selector(syncClipboard(_:)))
                pushItem.representedObject = machine
                menu.addItem(pushItem)
                let pullItem = actionItem(knownDarwin == false ? "从远端剪贴板同步 ←（远端非 macOS）" : "从远端剪贴板同步 ←", #selector(syncClipboardFromRemote(_:)))
                pullItem.representedObject = machine
                menu.addItem(pullItem)
                transferItems.append(contentsOf: [pushItem, pullItem])
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
                    transferItems.append(quickItem)
                }
                for directory in machine.directories {
                    let item = actionItem("📁 \(directory.name)", #selector(uploadToTarget(_:)))
                    item.representedObject = UploadTarget(machine: machine, directory: directory)
                    item.isEnabled = !appState.isBusy
                    menu.addItem(item)
                    transferItems.append(item)
                }
            }
        }

        menu.addItem(.separator())
        let settingsItem = actionItem("设置…", #selector(openSettings))
        settingsItem.keyEquivalent = ","
        menu.addItem(settingsItem)
        menu.addItem(actionItem("重载配置", #selector(reloadConfig)))
        menu.addItem(actionItem("打开日志", #selector(openLog)))
        let updateItem = NSMenuItem(
            title: "检查更新…",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        updateItem.target = updateController.controller
        updateItem.isEnabled = updateController.controller.updater.canCheckForUpdates
        updateItem.setAccessibilityIdentifier("check-for-updates")
        menu.addItem(updateItem)
        let quitItem = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        refreshPresentation()
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        TransferSummaryView.labelItem(title)
    }

    private func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.setAccessibilityIdentifier(NSStringFromSelector(action))
        return item
    }

    @objc private func showDetails() { appState.showTransferDetails() }

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

#if DEBUG
extension StatusMenuController {
    func debugTransfer(_ parts: [String]) {
        if parts.first == "open-menu" {
            // 不在 MainActor Task 内同步进入菜单 tracking，否则会阻塞后续验收事件。
            RunLoop.main.perform(inModes: [.common]) { [weak self] in
                MainActor.assumeIsolated { self?.statusItem.button?.performClick(nil) }
            }
            return
        }
        guard parts.count > 1 else { return }
        if parts[0] == "key" {
            let keys: [String: (UInt16, String)] = ["down": (125, "\u{f701}"), "return": (36, "\r"), "escape": (53, "\u{1b}")]
            if let (code, characters) = keys[parts[1]],
               let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                   windowNumber: statusItem.button?.window?.windowNumber ?? 0, context: nil,
                   characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code) {
                NSApp.postEvent(event, atStart: false)
            }
            return
        }
        if parts[0] == "reduce-motion" {
            debugReduceMotion = parts[1] == "system" ? nil : parts[1] == "on"
            refreshPresentation()
            return
        }
        if parts[0] == "appearance" {
            NSApp.appearance = parts[1] == "system" ? nil : NSAppearance(named: parts[1] == "dark" ? .darkAqua : .aqua)
            return
        }
        do {
            let url = URL(fileURLWithPath: parts[1])
            if parts[0] == "dump" {
                let state = appState.presentation
                let rect = statusItem.button?.window?.frame ?? .zero
                var snapshot: [String: Any] = [
                    "title": state.title, "subtitle": state.subtitle(), "feedback": state.feedback.rawValue,
                    "busy": state.isBusy, "retryable": appState.hasRetryableFailure,
                    "paths": appState.lastRemotePaths, "animation": animationTimer != nil,
                    "reduceMotion": reduceMotion, "summaryWidth": summaryView.frame.width,
                    "statusFrame": [rect.origin.x, rect.origin.y, rect.width, rect.height],
                    "accessibilityLabel": statusItem.button?.accessibilityLabel() ?? "",
                    "activationPolicy": NSApp.activationPolicy().rawValue,
                    "trackedWindows": DockPresence.debugWindowTitles,
                    "dockTransitions": DockPresence.debugTransitions,
                    "active": NSApp.isActive,
                ]
                if let record = state.record {
                    snapshot["id"] = record.id.uuidString
                    snapshot["files"] = record.content.fileNames
                    snapshot["message"] = record.message
                    snapshot["recordPaths"] = record.remotePaths
                    snapshot["bytes"] = record.content.byteCount
                    snapshot["characters"] = record.content.characterCount
                }
                try JSONSerialization.data(withJSONObject: snapshot, options: [.prettyPrinted, .sortedKeys]).write(to: url)
            } else if parts[0] == "export" {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                for scale in [1, 2] {
                    for dark in [false, true] {
                        for feedback in TransferPresentation.Feedback.allCases {
                            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 18 * scale, pixelsHigh: 18 * scale,
                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                            rep.size = NSSize(width: 18, height: 18)
                            NSGraphicsContext.saveGraphicsState()
                            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                            StatusBadgeRenderer.image(feedback: feedback).draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
                            (dark ? NSColor.white : NSColor.black).setFill()
                            NSRect(x: 0, y: 0, width: 18, height: 18).fill(using: .sourceIn)
                            NSGraphicsContext.restoreGraphicsState()
                            try rep.representation(using: .png, properties: [:])!.write(to: url.appendingPathComponent("\(dark ? "dark" : "light")-\(feedback.rawValue)-\(scale)x.png"))
                        }
                    }
                }
            }
        } catch {
            appState.log.error("DEBUG 传输验收导出失败：\(error.localizedDescription)")
        }
    }
}
#endif
