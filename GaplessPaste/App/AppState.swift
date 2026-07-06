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
    }

    init() {
        // ControlMaster socket 放 Caches：路径无空格（ssh -o 值按配置行分词，
        // Application Support 的空格会打断），且 unix socket 路径有长度上限
        let socketsDir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.reorx.gaplesspaste/sockets", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: socketsDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        commandBuilder = SSHCommandBuilder(controlPathDirectory: socketsDir.path)
        runner = SSHRunner(log: log)
        probeService = ProbeService(runner: runner, builder: commandBuilder)
        notifier.requestAuthorization()

        log.info("==== GaplessPaste 启动 (pid \(ProcessInfo.processInfo.processIdentifier)) ====")
        log.info("ControlPath 目录：\(socketsDir.path)")
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
                writePathsBackToClipboard: true
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
            return Payload(items: [(localURL.path, fileName)], writePathsBackToClipboard: false)
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
                let remotePaths = try await performTransfer(machine: machine, directory: directory, payload: payload)
                lastRemotePaths = remotePaths
                hasRetryableFailure = false
                retryAction = nil
                if payload.writePathsBackToClipboard {
                    pasteboard.writeText(remotePaths.joined(separator: "\n"))
                }
                let names = payload.items.map(\.desiredName).joined(separator: ", ")
                statusLine = "上次：✓ \(names) → \(machine.name)/\(directory.name)"
                log.info("上传成功：\n\(remotePaths.joined(separator: "\n"))")
                notifier.notify(
                    title: "已上传到 \(machine.name)/\(directory.name)",
                    body: remotePaths.joined(separator: "\n")
                )
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

    /// 探测 → 展开路径 → mkdir -p → 重名探测 → 逐个 scp，返回远端绝对路径
    private func performTransfer(machine: Machine, directory: RemoteDirectory, payload: Payload) async throws -> [String] {
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
        return remotePaths
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
