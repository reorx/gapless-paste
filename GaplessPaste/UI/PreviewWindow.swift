import AppKit
import SwiftUI
import GaplessPasteCore

// 预览远端目录窗口：左侧目录树（懒加载子目录），右侧文件预览。
// - 可开多个窗口，各自独立（互不共享状态）
// - 每窗口内存缓存：文件下载一次后切换回来瞬时加载（关窗即弃）
// - ⌘ 多选文件 → 右侧分栏并排预览，方便对比
// - pin 置顶：window.level = .floating

// MARK: - 树节点

@MainActor
final class PreviewNode: Identifiable, ObservableObject {
    /// id = 远端绝对路径（同窗口内唯一）
    let id: String
    let name: String
    let isDirectory: Bool
    @Published var isExpanded = false
    /// nil = 尚未加载；空数组 = 空目录
    @Published var children: [PreviewNode]?
    @Published var isLoadingChildren = false
    @Published var childrenError: String?

    init(path: String, name: String, isDirectory: Bool) {
        self.id = path
        self.name = name
        self.isDirectory = isDirectory
    }
}

// MARK: - 窗口模型

@MainActor
final class PreviewWindowModel: ObservableObject {
    enum PreviewState {
        case loading
        case image(NSImage)
        case text(String, truncated: Bool)
        case binary(byteCount: Int)
        case failed(String)
    }

    let machine: Machine
    let requestedPath: String

    @Published private(set) var root: PreviewNode?
    @Published private(set) var rootError: String?
    @Published var selection: Set<String> = []
    @Published var isPinned = false {
        didSet { onPinChange?(isPinned) }
    }
    /// 预览缓存：key = 远端路径。窗口存续期间不失效，切回已看过的文件瞬时加载
    @Published private(set) var previews: [String: PreviewState] = [:]

    var onPinChange: ((Bool) -> Void)?

    private let runner: SSHRunner
    private let builder: SSHCommandBuilder
    private let probeService: ProbeService
    private let log: LogService
    /// 已创建节点索引：选中集合（路径）→ 节点（判断文件/目录）
    private var nodesByPath: [String: PreviewNode] = [:]
    /// 本窗口私有的下载缓存目录，关窗清理
    private let cacheDirectory: URL

    init(machine: Machine, path: String, runner: SSHRunner, builder: SSHCommandBuilder, probeService: ProbeService, log: LogService) {
        self.machine = machine
        self.requestedPath = path
        self.runner = runner
        self.builder = builder
        self.probeService = probeService
        self.log = log
        cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GaplessPaste/preview-\(UUID().uuidString)", isDirectory: true)
    }

    /// 探测（~ 展开）→ 校验目录存在 → 列根目录
    func start() {
        rootError = nil
        root = nil
        Task {
            do {
                let probe = try await probeService.probe(machine.sshAlias)
                let absolutePath = probe.expandPath(requestedPath)
                log.info("预览远端目录：\(machine.name):\(absolutePath)")
                let quoted = SSHCommandBuilder.shellQuote(absolutePath)
                let command = "test -d \(quoted) && \(RemoteBrowse.listCommand(path: absolutePath))"
                let result = try await runner.run(builder.sshCommand(host: machine.sshAlias, remoteCommand: command), timeout: 30)
                guard result.succeeded else {
                    rootError = result.stderr.isEmpty ? "不是目录或不存在：\(absolutePath)" : result.firstStderrLine
                    return
                }
                let node = PreviewNode(path: absolutePath, name: absolutePath, isDirectory: true)
                node.children = makeChildren(of: node, from: result.stdout)
                node.isExpanded = true
                nodesByPath[node.id] = node
                root = node
            } catch {
                rootError = error.localizedDescription
            }
        }
    }

    /// 刷新：重列目录树并清空预览缓存
    func refresh() {
        selection = []
        previews = [:]
        nodesByPath = [:]
        try? FileManager.default.removeItem(at: cacheDirectory)
        start()
    }

    func loadChildrenIfNeeded(_ node: PreviewNode) {
        guard node.isDirectory, node.children == nil, !node.isLoadingChildren else { return }
        node.isLoadingChildren = true
        node.childrenError = nil
        Task {
            defer { node.isLoadingChildren = false }
            do {
                let result = try await runner.run(
                    builder.listDirectoryCommand(host: machine.sshAlias, remotePath: node.id),
                    timeout: 30
                )
                guard result.succeeded else {
                    node.childrenError = result.firstStderrLine
                    return
                }
                node.children = makeChildren(of: node, from: result.stdout)
            } catch {
                node.childrenError = error.localizedDescription
            }
        }
    }

    private func makeChildren(of parent: PreviewNode, from listing: String) -> [PreviewNode] {
        RemoteBrowse.parseListing(listing).map { entry in
            let node = PreviewNode(
                path: RemoteBrowse.joinPath(parent.id, entry.name),
                name: entry.name,
                isDirectory: entry.isDirectory
            )
            nodesByPath[node.id] = node
            return node
        }
    }

    /// 当前选中的文件（过滤掉目录），按路径稳定排序供分栏展示
    var selectedFiles: [PreviewNode] {
        selection
            .compactMap { nodesByPath[$0] }
            .filter { !$0.isDirectory }
            .sorted { $0.id < $1.id }
    }

    /// 选中变化时为尚无缓存的文件启动下载；已缓存的瞬时命中
    func ensurePreviews() {
        for node in selectedFiles where previews[node.id] == nil {
            previews[node.id] = .loading
            downloadAndPreview(node)
        }
    }

    private func downloadAndPreview(_ node: PreviewNode) {
        Task {
            do {
                try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
                let localURL = cacheDirectory.appendingPathComponent("\(UUID().uuidString)-\(node.name)")
                let result = try await runner.run(
                    builder.scpDownloadCommand(host: machine.sshAlias, remotePath: node.id, localPath: localURL.path),
                    timeout: 120
                )
                guard result.succeeded else {
                    previews[node.id] = .failed(result.firstStderrLine)
                    return
                }
                let data = try Data(contentsOf: localURL)
                previews[node.id] = Self.makePreview(fileName: node.name, data: data)
            } catch {
                previews[node.id] = .failed(error.localizedDescription)
            }
        }
    }

    private static func makePreview(fileName: String, data: Data) -> PreviewState {
        switch FilePreview.kind(forFileName: fileName) {
        case .image:
            guard let image = NSImage(data: data) else { return .failed("图像解码失败") }
            return .image(image)
        case .text:
            guard let decoded = FilePreview.decodeText(data) else { return .binary(byteCount: data.count) }
            return .text(decoded.text, truncated: decoded.truncated)
        }
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: cacheDirectory)
    }
}

// MARK: - 视图

struct PreviewWindowView: View {
    @ObservedObject var model: PreviewWindowModel

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HSplitView {
                sidebar
                    .frame(minWidth: 180, idealWidth: 240, maxWidth: 400)
                previewArea
                    .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 640, minHeight: 400)
        .onChange(of: model.selection) { model.ensurePreviews() }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Label("\(model.machine.name) : \(model.root?.id ?? model.requestedPath)", systemImage: "folder.badge.gearshape")
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .accessibilityIdentifier("preview-refresh")
            .help("重新加载目录树并清空预览缓存")
            Button {
                model.isPinned.toggle()
            } label: {
                Image(systemName: model.isPinned ? "pin.fill" : "pin")
            }
            .accessibilityIdentifier("preview-pin")
            .help(model.isPinned ? "取消置顶" : "置顶：悬浮于所有窗口之上")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var sidebar: some View {
        if let root = model.root {
            List(selection: $model.selection) {
                if let children = root.children, children.isEmpty {
                    Text("（空目录）").foregroundStyle(.tertiary)
                } else {
                    ForEach(root.children ?? []) { child in
                        PreviewNodeRow(node: child, model: model)
                    }
                }
            }
            .listStyle(.sidebar)
        } else if let error = model.rootError {
            errorPlaceholder(error)
        } else {
            VStack(spacing: 8) {
                ProgressView()
                Text("加载目录…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func errorPlaceholder(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(.orange)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("重试") { model.start() }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var previewArea: some View {
        let files = model.selectedFiles
        if files.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 36))
                    .foregroundStyle(.tertiary)
                Text("在左侧选择文件预览\n按住 ⌘ 多选可分栏对比")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(spacing: 0) {
                ForEach(files) { file in
                    PreviewPane(node: file, state: model.previews[file.id] ?? .loading)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if file.id != files.last?.id {
                        Divider()
                    }
                }
            }
        }
    }
}

/// 目录树的一行：目录用 DisclosureGroup 递归展开（首次展开触发懒加载），文件行可选中
private struct PreviewNodeRow: View {
    @ObservedObject var node: PreviewNode
    let model: PreviewWindowModel

    var body: some View {
        if node.isDirectory {
            DisclosureGroup(
                isExpanded: Binding(
                    get: { node.isExpanded },
                    set: { expanded in
                        node.isExpanded = expanded
                        if expanded { model.loadChildrenIfNeeded(node) }
                    }
                )
            ) {
                if let error = node.childrenError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                } else if let children = node.children {
                    if children.isEmpty {
                        Text("（空）").foregroundStyle(.tertiary)
                    } else {
                        ForEach(children) { child in
                            PreviewNodeRow(node: child, model: model)
                        }
                    }
                } else {
                    Text("加载中…").foregroundStyle(.tertiary)
                }
            } label: {
                Label(node.name, systemImage: "folder")
                    .lineLimit(1)
            }
        } else {
            Label(node.name, systemImage: FilePreview.kind(forFileName: node.name) == .image ? "photo" : "doc.text")
                .lineLimit(1)
                .tag(node.id)
        }
    }
}

/// 单个文件的预览栏：文件名标题 + 按状态渲染（加载中/图像/文本/二进制/失败）
private struct PreviewPane: View {
    let node: PreviewNode
    let state: PreviewWindowModel.PreviewState

    var body: some View {
        VStack(spacing: 0) {
            Text(node.name)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(.quaternary.opacity(0.5))
            Divider()
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            VStack(spacing: 8) {
                ProgressView()
                Text("下载中…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .image(let image):
            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        maxWidth: max(image.size.width, 1),
                        maxHeight: max(image.size.height, 1)
                    )
                    .padding(8)
            }
        case .text(let text, let truncated):
            VStack(spacing: 0) {
                if truncated {
                    Text("文件过大，仅展示前 \(DisplayFormatter.byteCountText(FilePreview.maxTextPreviewBytes))")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                        .background(.quaternary.opacity(0.4))
                }
                ScrollView {
                    Text(text)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
            }
        case .binary(let byteCount):
            VStack(spacing: 8) {
                Image(systemName: "doc.zipper")
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
                Text("二进制文件，无法预览（\(DisplayFormatter.byteCountText(byteCount))）")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28))
                    .foregroundStyle(.orange)
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - 窗口控制器

@MainActor
final class PreviewWindowController: NSObject, NSWindowDelegate {
    private let model: PreviewWindowModel
    private var window: NSWindow?
    /// 关窗回调：AppState 从窗口注册表移除本控制器
    var onClose: (() -> Void)?

    init(machine: Machine, path: String, runner: SSHRunner, builder: SSHCommandBuilder, probeService: ProbeService, log: LogService) {
        model = PreviewWindowModel(
            machine: machine, path: path,
            runner: runner, builder: builder, probeService: probeService, log: log
        )
        super.init()
        model.onPinChange = { [weak self] pinned in
            self?.window?.level = pinned ? .floating : .normal
        }
    }

    func show() {
        let hosting = NSHostingController(rootView: PreviewWindowView(model: model))
        let window = NSWindow(contentViewController: hosting)
        window.title = "🔍 \(model.machine.name) : \(model.requestedPath)"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 860, height: 540))
        window.delegate = self
        window.center()
        self.window = window
        model.start()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model.cleanup()
        onClose?()
    }
}
