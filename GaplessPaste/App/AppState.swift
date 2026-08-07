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
    private lazy var settingsController = SettingsWindowController(
        onSave: { [weak self] config in self?.applySettings(config) },
        openConfigFile: { [weak self] in self?.openConfig() }
    )

    /// 打开中的预览窗口（可多开），关窗时自移除
    private var previewControllers: [PreviewWindowController] = []

    private(set) var isBusy = false
    private(set) var statusLine: String?
    /// 上次操作（成功或失败）的完成时刻，菜单据此显示相对时间
    private(set) var lastFinishedAt: Date?
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
        // Caches / Application Support 前缀都超预算，只能落在 /tmp，0700 保证用户私有；
        // /tmp 会被系统周期清理，目录由 SSHRunner 在每次执行前幂等重建
        let socketsDir = SSHCommandBuilder.defaultControlPathDirectory(uid: getuid())
        commandBuilder = SSHCommandBuilder(controlPathDirectory: socketsDir)
        runner = SSHRunner(log: log, builder: commandBuilder)
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


    /// 快速上传（M4）：读剪贴板 → 按内容类型选该机器对应角色的默认目录 → 委托 upload 走完整流程。
    /// 文件引用 → .file 默认目录；图像 → .image 默认目录（仍弹重命名浮窗）；
    /// 纯文本引导去「同步剪贴板」、空剪贴板与未配置默认目录均以通知提示。
    func quickUpload(machine: Machine) {
        guard !isBusy else { return }
        let snapshot = pasteboard.snapshot()
        let content = PasteboardClassifier.classify(
            fileURLs: snapshot.fileURLs,
            imagePNGData: snapshot.imagePNGData,
            text: snapshot.text
        )
        log.info("触发快速上传 → \(machine.name)，剪贴板分类：\(describe(content))")
        let role: DirectoryRole
        switch content {
        case .fileReferences:
            role = .file
        case .imageData:
            role = .image
        case .text:
            notifier.notify(title: "GaplessPaste", body: "剪贴板是纯文本，请用「同步到远端剪贴板 →」")
            return
        case .empty:
            notifier.notify(title: "GaplessPaste", body: TransferRejection.emptyClipboard.userMessage)
            return
        }
        guard let directory = machine.defaultDirectory(for: role) else {
            let label = role == .file ? "文件" : "图像"
            notifier.notify(title: "GaplessPaste", body: "\(machine.name) 未配置\(label)默认目录，请在「设置…」里指定")
            return
        }
        log.info("快速上传目标目录：\(machine.name)/\(directory.name)（\(role.rawValue) 默认）")
        upload(machine: machine, directory: directory)
    }

    /// 已探测机器的平台（nil = 尚未探测）。菜单据此对非 Darwin 机器禁用「同步剪贴板」；
    /// 未探测的保持可用，点击时探测、发现非 Darwin 则提示（spec：非 Darwin 降级/禁用）
    func remoteIsDarwinIfKnown(machine: Machine) -> Bool? {
        probeService.cached(machine.sshAlias)?.isDarwin
    }

    /// 预览远端目录：弹输入框要路径（附近期路径快捷填充）→ 开独立预览窗口（可多开，各自缓存）
    func previewFolder(machine: Machine) {
        NSApp.activate(ignoringOtherApps: true)
        let recentsKey = "previewRecentPaths.\(machine.sshAlias)"
        let recents = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
        guard let path = PreviewPathPrompt.run(machineName: machine.name, recentPaths: recents) else { return }
        UserDefaults.standard.set(RecentPaths.updated(recents, adding: path), forKey: recentsKey)

        let controller = PreviewWindowController(
            machine: machine, path: path,
            runner: runner, builder: commandBuilder, probeService: probeService, log: log
        )
        controller.onClose = { [weak self, weak controller] in
            self?.previewControllers.removeAll { $0 === controller }
        }
        previewControllers.append(controller)
        controller.show()
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

    /// 打开设置窗口（草稿从当前内存配置初始化；解析失败时从空配置起步）
    func openSettings() {
        let config: Config
        if case .success(let current) = configStore.lastResult {
            config = current
        } else {
            config = Config(machines: [])
        }
        settingsController.show(config: config)
    }

    /// 设置界面落盘回调：写 config.json + 清探测缓存（同「重载配置」语义，但不弹通知）
    private func applySettings(_ config: Config) {
        do {
            try configStore.save(config)
            probeService.clearCache()
            log.info("设置已保存：\(config.machines.count) 台机器，探测缓存已清空")
        } catch {
            log.error("设置保存失败：\(error.localizedDescription)")
            notifier.notify(title: "设置保存失败", body: error.localizedDescription)
        }
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

    // MARK: - 拖拽上传（路径 C）

    /// DropPanel 目录行收到 drop：按文件引用模式上传（同路径 A），路径回传本地剪贴板
    func uploadDroppedFiles(_ urls: [URL], machine: Machine, directory: RemoteDirectory) {
        guard !isBusy else { return }
        let files = urls.filter(\.isFileURL)
        guard !files.isEmpty else {
            notifier.notify(title: "GaplessPaste", body: "拖拽内容里没有可上传的文件")
            return
        }
        log.info("拖拽上传 → \(machine.name)/\(directory.name)：\(files.map(\.lastPathComponent).joined(separator: ", "))")
        let payload = Payload(
            items: files.map { ($0.path, NameGenerator.sanitize($0.lastPathComponent)) },
            writePathsBackToClipboard: true,
            isImage: false
        )
        transfer(machine: machine, directory: directory, payload: payload)
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
                lastFinishedAt = Date()
                log.info("上传成功：\n\(joinedPaths)")
                notifier.notify(title: noteTitle, body: noteBody)
            } catch {
                statusLine = "上次：✗ \(error.localizedDescription)"
                lastFinishedAt = Date()
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

        // 与平台无关的拒绝先行（空剪贴板/非单个图片文件引用），不必等 ssh 探测
        if let rejection = TransferPlanner.contentRejection(forSync: content) {
            log.info("拒绝：\(rejection.userMessage)")
            notifier.notify(title: "GaplessPaste", body: rejection.userMessage)
            return
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
                lastFinishedAt = Date()
                log.info("同步剪贴板成功：\(summary) → \(machine.name)")
                notifier.notify(title: "已同步剪贴板到 \(machine.name)", body: "\(summary)，远端 Ctrl+V / ⌘V 可用")
            } catch {
                statusLine = "上次：✗ \(error.localizedDescription)"
                lastFinishedAt = Date()
                hasRetryableFailure = true
                retryAction = { [weak self] in
                    self?.sync(machine: machine, content: content)
                }
                log.error("同步剪贴板失败：\(error.localizedDescription)")
                notifier.notify(title: "同步剪贴板失败", body: error.localizedDescription)
            }
        }
    }

    // MARK: - 从远端剪贴板同步（远端 → 本机）

    /// 一次 ssh 拿图像（osascript 打印 «data PNGf<hex>»，本机 hex 解码）；
    /// 非图像（哨兵命中）再 ssh pbpaste 拿文本；空文本 = 远端剪贴板为空
    func syncClipboardFromRemote(machine: Machine) {
        Task {
            guard !isBusy else { return }
            isBusy = true
            statusLine = "进行中：从 \(machine.name) 同步剪贴板…"
            defer { isBusy = false }
            do {
                let probe = try await probeService.probe(machine.sshAlias)
                guard let extract = RemoteClipboard.imageExtractionCommand(probe: probe) else {
                    // 非 Darwin：与推送方向同一拒绝语义，探测结果已入缓存，菜单下次打开即置灰
                    statusLine = nil
                    log.info("拒绝：\(SyncRejection.remoteClipboardUnsupported.userMessage)")
                    notifier.notify(title: "GaplessPaste", body: SyncRejection.remoteClipboardUnsupported.userMessage)
                    return
                }
                // 图像经 hex 回传体积翻倍，超时放宽到 60s
                let result = try await runner.run(commandBuilder.sshCommand(host: machine.sshAlias, remoteCommand: extract), timeout: 60)
                guard result.succeeded else {
                    throw AppError.commandFailed(operation: "读取远端剪贴板", detail: result.firstStderrLine)
                }
                let summary: String
                switch RemoteClipboard.parseImageExtractionOutput(result.stdout) {
                case .imagePNG(let png):
                    pasteboard.writeImagePNG(png)
                    summary = "图像 \(DisplayFormatter.byteCountText(png.count))"
                case .notImage:
                    let textCommand = RemoteClipboard.textExtractionCommand(probe: probe)!
                    let textResult = try await runner.run(commandBuilder.sshCommand(host: machine.sshAlias, remoteCommand: textCommand), timeout: 20)
                    guard textResult.succeeded else {
                        throw AppError.commandFailed(operation: "读取远端剪贴板文本", detail: textResult.firstStderrLine)
                    }
                    guard !textResult.stdout.isEmpty else {
                        statusLine = nil
                        log.info("从 \(machine.name) 同步剪贴板：远端剪贴板为空")
                        notifier.notify(title: "GaplessPaste", body: "\(machine.name) 的剪贴板是空的")
                        return
                    }
                    pasteboard.writeText(textResult.stdout)
                    summary = "文本 \(textResult.stdout.count) 字符"
                case .unrecognized:
                    throw AppError.commandFailed(operation: "读取远端剪贴板", detail: "无法识别的远端输出")
                }
                hasRetryableFailure = false
                retryAction = nil
                statusLine = "上次：✓ \(machine.name) 剪贴板（\(summary)）→ 本机"
                lastFinishedAt = Date()
                log.info("从远端同步剪贴板成功：\(machine.name) → 本机，\(summary)")
                notifier.notify(title: "已从 \(machine.name) 同步剪贴板", body: "\(summary)，本机 ⌘V 可用")
            } catch {
                statusLine = "上次：✗ \(error.localizedDescription)"
                lastFinishedAt = Date()
                hasRetryableFailure = true
                retryAction = { [weak self] in
                    self?.syncClipboardFromRemote(machine: machine)
                }
                log.error("从远端同步剪贴板失败：\(error.localizedDescription)")
                notifier.notify(title: "从远端同步剪贴板失败", body: error.localizedDescription)
            }
        }
    }

    /// 图像：写本地临时 PNG → scp 到固定远端临时路径（每次覆盖）→ osascript 注入；
    /// 单个图片文件引用：读文件转 PNG 后走同一图像路径；
    /// 文本：直接 ssh pbcopy（stdin 传输）。返回通知用的内容摘要
    private func performSync(machine: Machine, probe: ProbeResult, content: ClassifiedContent) async throws -> String {
        let host = machine.sshAlias
        switch content {
        case .imageData(let png):
            try await syncImage(png: png, host: host, probe: probe)
            return "图像 \(DisplayFormatter.byteCountText(png.count))"
        case .fileReferences(let urls):
            // 单个图片文件（contentRejection 已保证），转 PNG 后与图像数据同路径
            guard let url = urls.first, let png = PasteboardService.pngData(fromImageFile: url) else {
                throw AppError.commandFailed(operation: "读取图片文件", detail: urls.first?.lastPathComponent ?? "")
            }
            try await syncImage(png: png, host: host, probe: probe)
            return "图片文件 \(url.lastPathComponent)（\(DisplayFormatter.byteCountText(png.count))）"
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
        case .empty:
            throw AppError.commandFailed(operation: "同步剪贴板", detail: "不支持的内容类型") // 已被前置拒绝，防御分支
        }
    }

    /// 同步图像的公共路径：写本地临时 PNG → mkdir 远端临时目录 → scp 固定路径（每次覆盖）→ osascript 注入
    private func syncImage(png: Data, host: String, probe: ProbeResult) async throws {
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
