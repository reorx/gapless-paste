import AppKit
import GaplessPasteCore

enum AppError: Error, LocalizedError {
    case probeFailed(alias: String, detail: String)
    case commandFailed(operation: String, detail: String)
    case imageWriteFailed

    var errorDescription: String? {
        switch self {
        case .probeFailed(let alias, let detail):
            return "探测 \(alias) 失败：\(detail)"
        case .commandFailed(let operation, let detail):
            return "\(operation)失败：\(detail)"
        case .imageWriteFailed:
            return "图像写入临时文件失败"
        }
    }
}

// 全局状态：桥接 Core 的 Planner 与各 Service。
// 单任务串行：isBusy 期间菜单目录项禁用（spec 非目标：不做传输队列）。

@MainActor
final class AppState {
    let configStore = ConfigStore()
    let log = LogService()
    private let pasteboard = PasteboardService()
    private let notifier = NotificationService()
    private let runner: SSHRunner
    private let renamePopup = RenamePopup()
    private let commandBuilder: SSHCommandBuilder
    private let probeService: ProbeService

    private(set) var isBusy = false
    private(set) var statusLine: String?
    private(set) var lastRemotePaths: [String] = []
    private(set) var hasRetryableFailure = false
    private var retryAction: (() -> Void)?

    /// 待上传的本地文件 + 期望的远端文件名（重试时原样重放，图像不再重新弹窗）
    private struct Payload {
        let items: [(localPath: String, desiredName: String)]
        let writePathsBackToClipboard: Bool
        /// 图像模式：上传后 Darwin 注入远端剪贴板，非 Darwin 降级为路径模式
        let isImage: Bool
    }

    init() {
        // ControlMaster socket 目录：必须短（sun_path 104 字节上限，预算见
        // SSHCommandBuilder）且无空格（ssh -o 值按配置行分词）。
        // Caches / Application Support 前缀都超预算，只能落在 /tmp，0700 保证用户私有
        let socketsDir = SSHCommandBuilder.defaultControlPathDirectory(uid: getuid())
        try? FileManager.default.createDirectory(
            atPath: socketsDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        commandBuilder = SSHCommandBuilder(controlPathDirectory: socketsDir)
        runner = SSHRunner(log: log)
        probeService = ProbeService(runner: runner, builder: commandBuilder)
        notifier.requestAuthorization()

        log.info("==== GaplessPaste 启动 (pid \(ProcessInfo.processInfo.processIdentifier)) ====")
        log.info("ControlPath 目录：\(socketsDir)（socket 路径预算 \(SSHCommandBuilder.predictedSocketPathLength(forDirectory: socketsDir))/\(SSHCommandBuilder.maxUnixSocketPathLength)）")
        switch configStore.lastResult {
        case .success(let config):
            log.info("配置加载成功：\(config.machines.count) 台机器")
        case .failure(let error):
            log.error("配置加载失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 菜单动作

    func upload(machine: Machine, directory: RemoteDirectory) {
        Task { await prepareAndTransfer(machine: machine, directory: directory) }
    }

    func syncClipboard(machine: Machine) {
        Task { await prepareAndSync(machine: machine) }
    }

    /// 已探测机器的平台（nil = 尚未探测）。菜单据此对非 Darwin 机器禁用「同步剪贴板」；
    /// 未探测的保持可用，点击时探测、发现非 Darwin 则提示（spec：非 Darwin 降级/禁用）
    func remoteIsDarwinIfKnown(machine: Machine) -> Bool? {
        probeService.cached(machine.sshAlias)?.isDarwin
    }

    func copyLastRemotePaths() {
        guard !lastRemotePaths.isEmpty else { return }
        pasteboard.writeText(lastRemotePaths.joined(separator: "\n"))
    }

    func retryLastOperation() {
        retryAction?()
    }

    func openConfig() {
        configStore.openInEditor()
    }

    func openLog() {
        log.openInViewer()
    }

    func reloadConfig() {
        configStore.load()
        probeService.clearCache()
        switch configStore.lastResult {
        case .success(let config):
            log.info("配置已重载：\(config.machines.count) 台机器，探测缓存已清空")
            notifier.notify(title: "GaplessPaste", body: "配置已重载（\(config.machines.count) 台机器），探测缓存已清空")
        case .failure(let error):
            log.error("配置重载失败：\(error.localizedDescription)")
            notifier.notify(title: "配置解析失败", body: error.localizedDescription)
        }
    }

    // MARK: - 上传流程

    private func prepareAndTransfer(machine: Machine, directory: RemoteDirectory) async {
        guard !isBusy else { return }
        let snapshot = pasteboard.snapshot()
        let content = PasteboardClassifier.classify(
            fileURLs: snapshot.fileURLs,
            imagePNGData: snapshot.imagePNGData,
            text: snapshot.text
        )
        log.info("触发上传 → \(machine.name)/\(directory.name)，剪贴板分类：\(describe(content))")
        if case .rejected(let rejection) = TransferPlanner.plan(for: content) {
            log.info("拒绝：\(rejection.userMessage)")
            notifier.notify(title: "GaplessPaste", body: rejection.userMessage)
            return
        }

        let payload: Payload
        switch content {
        case .fileReferences(let urls):
            // 按原文件名上传（多文件），清洗规则统一适用，路径回传本地剪贴板
            payload = Payload(
                items: urls.map { ($0.path, NameGenerator.sanitize($0.lastPathComponent)) },
                writePathsBackToClipboard: true,
                isImage: false
            )
        case .imageData(let png):
            // 重命名浮窗（Enter 确认 / Esc 取消），M1 不覆盖本地剪贴板
            guard let payloadFromImage = await promptAndStageImage(png: png, machine: machine, directory: directory) else {
                log.info("图像上传取消（用户 Esc 或图像写盘失败）")
                return // 用户取消，剪贴板不动，静默返回
            }
            payload = payloadFromImage
        case .text, .empty:
            return // 已被 plan 拒绝
        }

        transfer(machine: machine, directory: directory, payload: payload)
    }

    private func promptAndStageImage(png: Data, machine: Machine, directory: RemoteDirectory) async -> Payload? {
        let defaultName = NameGenerator.defaultImageName(for: Date())
        let defaultStem = String(defaultName.dropLast(".png".count))
        guard let image = NSImage(data: png),
              let stem = await renamePopup.requestImageStem(
                  defaultStem: defaultStem,
                  image: image,
                  targetLabel: "\(machine.name)/\(directory.name)"
              )
        else { return nil }

        let fileName = NameGenerator.sanitize(stem) + ".png"
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GaplessPaste/\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let localURL = tempDir.appendingPathComponent(fileName)
            try png.write(to: localURL)
            return Payload(items: [(localURL.path, fileName)], writePathsBackToClipboard: false, isImage: true)
        } catch {
            notifier.notify(title: "上传失败", body: AppError.imageWriteFailed.localizedDescription)
            return nil
        }
    }

    private func transfer(machine: Machine, directory: RemoteDirectory, payload: Payload) {
        Task {
            guard !isBusy else { return }
            isBusy = true
            statusLine = "进行中：上传到 \(machine.name)/\(directory.name)…"
            defer { isBusy = false }
            do {
                let (probe, remotePaths) = try await performTransfer(machine: machine, directory: directory, payload: payload)
                lastRemotePaths = remotePaths
                hasRetryableFailure = false
                retryAction = nil
                if payload.writePathsBackToClipboard {
                    pasteboard.writeText(remotePaths.joined(separator: "\n"))
                }
                let names = payload.items.map(\.desiredName).joined(separator: ", ")
                let joinedPaths = remotePaths.joined(separator: "\n")
                var noteTitle = "已上传到 \(machine.name)/\(directory.name)"
                var noteBody = joinedPaths
                if payload.isImage {
                    if let inject = RemoteClipboard.imageInjectionCommand(probe: probe, remoteImagePath: remotePaths[0]) {
                        // M2：图像上传成功后追加注入远端剪贴板，远端 Claude Code 可直接 Ctrl+V。
                        // 注入失败不当作整体失败（上传已成功，重试会造成重名副本），
                        // 路径仍可经「拷贝上次上传的远端路径」取回
                        let result = try await runner.run(commandBuilder.sshCommand(host: machine.sshAlias, remoteCommand: inject), timeout: 20)
                        if result.succeeded {
                            noteTitle = "已上传并注入远端剪贴板"
                            noteBody = "\(joinedPaths)\n远端 Ctrl+V 可用"
                        } else {
                            log.error("注入远端剪贴板失败：\(result.firstStderrLine)")
                            noteTitle = "已上传，但注入远端剪贴板失败"
                            noteBody = "\(result.firstStderrLine)\n\(joinedPaths)"
                        }
                    } else {
                        // 非 Darwin 无剪贴板注入：自动降级为路径模式
                        pasteboard.writeText(joinedPaths)
                        noteBody = "远端无剪贴板注入，已拷贝路径\n\(joinedPaths)"
                    }
                }
                statusLine = "上次：✓ \(names) → \(machine.name)/\(directory.name)"
                log.info("上传成功：\n\(joinedPaths)")
                notifier.notify(title: noteTitle, body: noteBody)
            } catch {
                statusLine = "上次：✗ \(error.localizedDescription)"
                hasRetryableFailure = true
                retryAction = { [weak self] in
                    self?.transfer(machine: machine, directory: directory, payload: payload)
                }
                log.error("上传失败：\(error.localizedDescription)")
                notifier.notify(title: "上传失败", body: error.localizedDescription)
            }
        }
    }

    /// 探测 → 展开路径 → mkdir -p → 重名探测 → 逐个 scp，返回探测结果与远端绝对路径
    private func performTransfer(machine: Machine, directory: RemoteDirectory, payload: Payload) async throws -> (ProbeResult, [String]) {
        let host = machine.sshAlias
        let probe = try await probeService.probe(host)
        let remoteDir = probe.expandPath(directory.path)
        log.info("探测 \(host)：home=\(probe.home) uname=\(probe.unameString)，目标目录 \(remoteDir)")

        let mkdir = try await runner.run(commandBuilder.mkdirCommand(host: host, remoteDirectory: remoteDir), timeout: 20)
        guard mkdir.succeeded else {
            throw AppError.commandFailed(operation: "创建远端目录", detail: mkdir.firstStderrLine)
        }

        // 重名策略：test -e 探测，存在则扩展名前追加 -1、-2 递增；
        // claimed 防止同批多个同名文件互相覆盖
        var claimed = Set<String>()
        var remotePaths: [String] = []
        for item in payload.items {
            var candidate = item.desiredName
            var index = 0
            while true {
                if !claimed.contains(candidate) {
                    let exists = try await remoteExists(host: host, path: "\(remoteDir)/\(candidate)")
                    if !exists { break }
                }
                index += 1
                candidate = NameGenerator.appendingSuffix(item.desiredName, index: index)
            }
            claimed.insert(candidate)

            let remotePath = "\(remoteDir)/\(candidate)"
            let scp = try await runner.run(
                commandBuilder.scpCommand(localPath: item.localPath, host: host, remotePath: remotePath),
                timeout: 300
            )
            guard scp.succeeded else {
                throw AppError.commandFailed(operation: "上传 \(item.desiredName) ", detail: scp.firstStderrLine)
            }
            remotePaths.append(remotePath)
        }
        return (probe, remotePaths)
    }

    // MARK: - 同步剪贴板（路径 B）

    /// 读剪贴板 → 内容拒绝判定（无需探测）→ 探测平台 → 按 syncPlan 执行
    private func prepareAndSync(machine: Machine) async {
        guard !isBusy else { return }
        let snapshot = pasteboard.snapshot()
        let content = PasteboardClassifier.classify(
            fileURLs: snapshot.fileURLs,
            imagePNGData: snapshot.imagePNGData,
            text: snapshot.text
        )
        log.info("触发同步剪贴板 → \(machine.name)，剪贴板分类：\(describe(content))")

        // 与平台无关的拒绝先行，空剪贴板/文件引用不必等 ssh 探测
        switch content {
        case .empty:
            notifier.notify(title: "GaplessPaste", body: SyncRejection.emptyClipboard.userMessage)
            return
        case .fileReferences:
            notifier.notify(title: "GaplessPaste", body: SyncRejection.fileReferencesNotSyncable.userMessage)
            return
        case .imageData, .text:
            break
        }
        sync(machine: machine, content: content)
    }

    private func sync(machine: Machine, content: ClassifiedContent) {
        Task {
            guard !isBusy else { return }
            isBusy = true
            statusLine = "进行中：同步剪贴板到 \(machine.name)…"
            defer { isBusy = false }
            do {
                let probe = try await probeService.probe(machine.sshAlias)
                guard case .steps = TransferPlanner.syncPlan(for: content, remoteIsDarwin: probe.isDarwin) else {
                    // 此处只剩非 Darwin 一种拒绝（内容拒绝已在 prepareAndSync 先行）；
                    // 探测结果已入缓存，菜单下次打开即置灰
                    statusLine = nil
                    log.info("拒绝：\(SyncRejection.remoteClipboardUnsupported.userMessage)")
                    notifier.notify(title: "GaplessPaste", body: SyncRejection.remoteClipboardUnsupported.userMessage)
                    return
                }
                let summary = try await performSync(machine: machine, probe: probe, content: content)
                hasRetryableFailure = false
                retryAction = nil
                statusLine = "上次：✓ 剪贴板（\(summary)）→ \(machine.name)"
                log.info("同步剪贴板成功：\(summary) → \(machine.name)")
                notifier.notify(title: "已同步剪贴板到 \(machine.name)", body: "\(summary)，远端 Ctrl+V / ⌘V 可用")
            } catch {
                statusLine = "上次：✗ \(error.localizedDescription)"
                hasRetryableFailure = true
                retryAction = { [weak self] in
                    self?.sync(machine: machine, content: content)
                }
                log.error("同步剪贴板失败：\(error.localizedDescription)")
                notifier.notify(title: "同步剪贴板失败", body: error.localizedDescription)
            }
        }
    }

    /// 图像：写本地临时 PNG → scp 到固定远端临时路径（每次覆盖）→ osascript 注入；
    /// 文本：直接 ssh pbcopy（stdin 传输）。返回通知用的内容摘要
    private func performSync(machine: Machine, probe: ProbeResult, content: ClassifiedContent) async throws -> String {
        let host = machine.sshAlias
        switch content {
        case .imageData(let png):
            let localURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("GaplessPaste/clipboard-sync.png")
            do {
                try FileManager.default.createDirectory(at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try png.write(to: localURL)
            } catch {
                throw AppError.imageWriteFailed
            }

            let tempDir = RemoteClipboard.syncTemporaryDirectory(probe: probe)
            let tempPath = RemoteClipboard.syncTemporaryPath(probe: probe)
            let mkdir = try await runner.run(commandBuilder.mkdirCommand(host: host, remoteDirectory: tempDir), timeout: 20)
            guard mkdir.succeeded else {
                throw AppError.commandFailed(operation: "创建远端临时目录", detail: mkdir.firstStderrLine)
            }
            let scp = try await runner.run(commandBuilder.scpCommand(localPath: localURL.path, host: host, remotePath: tempPath), timeout: 300)
            guard scp.succeeded else {
                throw AppError.commandFailed(operation: "上传剪贴板图像", detail: scp.firstStderrLine)
            }
            // 平台已在 syncPlan 分支确认为 Darwin，注入命令必然非 nil
            let inject = RemoteClipboard.imageInjectionCommand(probe: probe, remoteImagePath: tempPath)!
            let result = try await runner.run(commandBuilder.sshCommand(host: host, remoteCommand: inject), timeout: 20)
            guard result.succeeded else {
                throw AppError.commandFailed(operation: "注入远端剪贴板", detail: result.firstStderrLine)
            }
            return "图像 \(png.count) bytes"
        case .text(let text):
            let inject = RemoteClipboard.textInjectionCommand(probe: probe)!
            let result = try await runner.run(
                commandBuilder.sshCommand(host: host, remoteCommand: inject),
                timeout: 20,
                stdin: Data(text.utf8)
            )
            guard result.succeeded else {
                throw AppError.commandFailed(operation: "注入远端剪贴板", detail: result.firstStderrLine)
            }
            return "文本 \(text.count) 字符"
        case .fileReferences, .empty:
            throw AppError.commandFailed(operation: "同步剪贴板", detail: "不支持的内容类型") // 已被前置拒绝，防御分支
        }
    }

    private func describe(_ content: ClassifiedContent) -> String {
        switch content {
        case .fileReferences(let urls):
            return "文件引用 ×\(urls.count)（\(urls.map(\.lastPathComponent).joined(separator: ", "))）"
        case .imageData(let data):
            return "图像数据 \(data.count) bytes"
        case .text(let text):
            return "文本 \(text.count) 字符"
        case .empty:
            return "空"
        }
    }

    private func remoteExists(host: String, path: String) async throws -> Bool {
        let result = try await runner.run(commandBuilder.testExistsCommand(host: host, remotePath: path), timeout: 20)
        switch result.exitCode {
        case 0: return true
        case 1: return false
        default:
            throw AppError.commandFailed(operation: "重名探测", detail: result.firstStderrLine)
        }
    }
}
