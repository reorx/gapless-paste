import AppKit
import SwiftUI
import GaplessPasteCore

// 预览远端目录窗口：左侧目录树（懒加载子目录），右侧文件预览。
// - 可开多个窗口，各自独立（互不共享状态）
// - 文件缓存持久化：下载落到 ~/Library/Caches/GaplessPaste/preview/（机器-路径-文件
//   定位见 Core PreviewCache），跨窗口、跨启动命中即免下载；分栏工具栏的刷新按钮强制重新下载
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
    /// 内存预览状态：key = 远端路径。窗口存续期间不失效，切回已看过的文件瞬时加载
    @Published private(set) var previews: [String: PreviewState] = [:]
    /// 已落到持久化缓存的文件：key = 远端路径。复制/下载按钮由此取本地文件
    /// （二进制文件不可预览但同样已下载，可复制/下载）
    @Published private(set) var downloadedFiles: [String: URL] = [:]
    /// 复制/下载动作的短暂反馈（顶栏展示，3s 自动消失）
    @Published private(set) var actionFeedback: String?
    /// 图像缩放倍率：key = 远端路径，缺省 = fit 模式（适应窗口，不放大超过原图）
    @Published private(set) var imageZoom: [String: CGFloat] = [:]
    /// 连接缩放：开启后任一图片的缩放操作同步到所有选中图片
    @Published var zoomLinked = false
    /// 连接滚动：开启后任一图片的滚动位置同步到其他分栏
    @Published var scrollLinked = false
    /// 连接滚动的最近一次用户滚动位置（归一化 0...1，x/y 各为可滚动范围的比例）
    @Published var linkedScrollFraction: CGPoint?

    var onPinChange: ((Bool) -> Void)?
    private var feedbackTask: Task<Void, Never>?

    private let runner: SSHRunner
    private let builder: SSHCommandBuilder
    private let probeService: ProbeService
    private let log: LogService
    /// 已创建节点索引：选中集合（路径）→ 节点（判断文件/目录）
    private var nodesByPath: [String: PreviewNode] = [:]
    /// 持久化缓存根目录：跨窗口、跨启动共享，不随关窗清理
    private static let persistentCacheRoot = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("GaplessPaste/preview", isDirectory: true)

    init(machine: Machine, path: String, runner: SSHRunner, builder: SSHCommandBuilder, probeService: ProbeService, log: LogService) {
        self.machine = machine
        self.requestedPath = path
        self.runner = runner
        self.builder = builder
        self.probeService = probeService
        self.log = log
    }

    /// 该远端文件在持久化缓存中的固定落点（机器-路径-文件 稳定映射）
    private func cacheURL(for node: PreviewNode) -> URL {
        Self.persistentCacheRoot.appendingPathComponent(
            PreviewCache.relativePath(sshAlias: machine.sshAlias, remotePath: node.id)
        )
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

    /// 刷新：重列目录树并清空内存预览状态。磁盘缓存保留（重选文件仍瞬时命中），
    /// 要强制重新下载某个文件用分栏工具栏的刷新按钮（refreshFile）
    func refresh() {
        selection = []
        previews = [:]
        downloadedFiles = [:]
        imageZoom = [:]
        nodesByPath = [:]
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

    /// 当前选中且已成功以图像预览的文件路径（连接缩放的同步目标）
    var selectedImagePaths: [String] {
        selectedFiles.map(\.id).filter {
            if case .image = previews[$0] { return true }
            return false
        }
    }

    /// 当前缩放倍率；nil = fit 模式
    func zoom(for path: String) -> CGFloat? {
        imageZoom[path]
    }

    /// 设置缩放（nil = 回到 fit）。连接缩放开启时同步到所有选中图片
    func setZoom(_ value: CGFloat?, for path: String) {
        let clamped = value.map { CGFloat(PreviewZoom.clamp(Double($0))) }
        var targets = zoomLinked ? selectedImagePaths : [path]
        if !targets.contains(path) { targets.append(path) }
        for target in targets {
            imageZoom[target] = clamped
        }
    }

    /// 选中变化时为尚无内存状态的文件加载预览：持久化缓存命中直接读盘，否则下载
    func ensurePreviews() {
        for node in selectedFiles where previews[node.id] == nil {
            previews[node.id] = .loading
            let cached = cacheURL(for: node)
            if FileManager.default.fileExists(atPath: cached.path) {
                loadFromCache(node, localURL: cached)
            } else {
                downloadAndPreview(node)
            }
        }
    }

    /// 单文件强制刷新：忽略持久化缓存重新下载，成功后更新缓存
    func refreshFile(_ node: PreviewNode) {
        if case .some(.loading) = previews[node.id] { return }
        previews[node.id] = .loading
        downloadedFiles[node.id] = nil
        log.info("预览窗口：强制刷新 \(machine.name):\(node.id)")
        downloadAndPreview(node)
    }

    private func loadFromCache(_ node: PreviewNode, localURL: URL) {
        do {
            let data = try Data(contentsOf: localURL)
            downloadedFiles[node.id] = localURL
            previews[node.id] = Self.makePreview(fileName: node.name, data: data)
        } catch {
            // 缓存文件读不出来（被系统/用户清理了一半等）→ 按未缓存重新下载
            downloadAndPreview(node)
        }
    }

    private func downloadAndPreview(_ node: PreviewNode) {
        Task {
            do {
                // 缓存路径末段保留原始文件名：复制到剪贴板 / 下载另存时拿到的就是原名文件。
                // 先下到同目录临时名再替换，避免多窗口同时下载/刷新读到半截文件
                let target = cacheURL(for: node)
                let directory = target.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let partial = directory.appendingPathComponent(".part-\(UUID().uuidString)")
                let result = try await runner.run(
                    builder.scpDownloadCommand(host: machine.sshAlias, remotePath: node.id, localPath: partial.path),
                    timeout: 120
                )
                guard result.succeeded else {
                    try? FileManager.default.removeItem(at: partial)
                    previews[node.id] = .failed(result.firstStderrLine)
                    return
                }
                let data = try Data(contentsOf: partial)
                if FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.removeItem(at: target)
                }
                try FileManager.default.moveItem(at: partial, to: target)
                downloadedFiles[node.id] = target
                previews[node.id] = Self.makePreview(fileName: node.name, data: data)
            } catch {
                previews[node.id] = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - 复制 / 下载

    /// ⌘C：把选中的、已下载完成的文件以文件引用写入本地剪贴板（Finder ⌘V 可粘贴出文件）
    func copySelectedFiles() {
        copyFiles(selectedFiles)
    }

    func copyFiles(_ nodes: [PreviewNode]) {
        let urls = nodes.compactMap { downloadedFiles[$0.id] }
        guard !urls.isEmpty else {
            showFeedback("文件尚未下载完成")
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
        log.info("预览窗口：已复制 \(urls.count) 个文件引用到本地剪贴板")
        showFeedback(urls.count == 1 ? "已复制 \(nodes[0].name)" : "已复制 \(urls.count) 个文件")
    }

    /// 下载按钮：NSSavePanel 选位置，把缓存文件拷贝过去（无需重新走 scp）
    func saveFile(_ node: PreviewNode) {
        guard let localURL = downloadedFiles[node.id] else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = node.name
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            // savePanel 已向用户确认过覆盖，这里直接替换
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: localURL, to: destination)
            log.info("预览窗口：\(node.id) 已另存到 \(destination.path)")
            showFeedback("已下载到 \(destination.path)")
        } catch {
            showFeedback("下载失败：\(error.localizedDescription)")
        }
    }

    /// 该文件是否已在本地缓存（复制/下载按钮的可用条件）
    func canExport(_ node: PreviewNode) -> Bool {
        downloadedFiles[node.id] != nil
    }

    private func showFeedback(_ message: String) {
        actionFeedback = message
        feedbackTask?.cancel()
        feedbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.actionFeedback = nil
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
}

// MARK: - 视图

struct PreviewWindowView: View {
    @ObservedObject var model: PreviewWindowModel

    /// 侧栏宽度只由用户拖动分割条改变（HSplitView 会在右侧内容变化时重排导致宽度跳变，故自绘分割条）
    @State private var sidebarWidth: CGFloat = 240
    @State private var sidebarDragBaseWidth: CGFloat?

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 0) {
                sidebar
                    .frame(width: sidebarWidth)
                splitter
                previewArea
                    .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 640, minHeight: 400)
        .onChange(of: model.selection) { model.ensurePreviews() }
        .background {
            // 复制快捷键：⌘C（macOS 惯例）与 ⌃C 都接住，把选中文件以文件引用写入剪贴板。
            // 隐藏按钮承载 keyboardShortcut，会先于文本选区的 copy 响应
            Button("") { model.copySelectedFiles() }
                .keyboardShortcut("c", modifiers: .command)
                .hidden()
            Button("") { model.copySelectedFiles() }
                .keyboardShortcut("c", modifiers: .control)
                .hidden()
        }
    }

    /// 分割条：1pt 分隔线 + 9pt 隐形拖动热区，拖动只改 sidebarWidth，布局重排不会影响它
    private var splitter: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .overlay {
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .global)
                            .onChanged { value in
                                let base = sidebarDragBaseWidth ?? sidebarWidth
                                sidebarDragBaseWidth = base
                                sidebarWidth = min(500, max(160, base + value.translation.width))
                            }
                            .onEnded { _ in sidebarDragBaseWidth = nil }
                    )
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
            }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Label("\(model.machine.name) : \(model.root?.id ?? model.requestedPath)", systemImage: "folder.badge.gearshape")
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
            Spacer()
            if let feedback = model.actionFeedback {
                Text(feedback)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            if model.selectedImagePaths.count >= 2 {
                Button {
                    model.zoomLinked.toggle()
                } label: {
                    Label("连接 Zoom", systemImage: model.zoomLinked ? "link.circle.fill" : "link")
                }
                .foregroundStyle(model.zoomLinked ? Color.accentColor : Color.primary)
                .accessibilityIdentifier("preview-zoom-link")
                .help(model.zoomLinked ? "断开连接缩放" : "连接缩放：任一图片缩放时其他图片同步")
                Button {
                    model.scrollLinked.toggle()
                } label: {
                    Label("连接 Scroll", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                }
                .foregroundStyle(model.scrollLinked ? Color.accentColor : Color.primary)
                .accessibilityIdentifier("preview-scroll-link")
                .help(model.scrollLinked ? "断开连接滚动" : "连接滚动：任一图片滚动时其他图片同步位置")
            }
            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .accessibilityIdentifier("preview-refresh")
            .help("重新加载目录树（文件磁盘缓存保留，单文件强制刷新用分栏上的刷新按钮）")
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
                    PreviewPane(
                        node: file,
                        state: model.previews[file.id] ?? .loading,
                        canExport: model.canExport(file),
                        zoom: model.zoom(for: file.id),
                        onZoomChange: { model.setZoom($0, for: file.id) },
                        scrollSync: model.scrollLinked ? model.linkedScrollFraction : nil,
                        onScrollChange: { [weak model] fraction in
                            guard let model, model.scrollLinked else { return }
                            model.linkedScrollFraction = fraction
                        },
                        onRefresh: { model.refreshFile(file) },
                        onCopy: { model.copyFiles([file]) },
                        onSave: { model.saveFile(file) }
                    )
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

/// 单个文件的预览栏：标题栏（文件名 + 操作按钮组）+ 按状态渲染（加载中/图像/文本/二进制/失败）。
/// 图像预览缩放：zoom == nil 为 fit 模式（适应窗口、不放大超过原图）；
/// 标题栏 −/百分比/＋/fit，内容区 pinch 手势；百分比点击还原 100%，fit 按钮回到适应窗口
private struct PreviewPane: View {
    let node: PreviewNode
    let state: PreviewWindowModel.PreviewState
    let canExport: Bool
    /// nil = fit 模式；缩放状态在窗口模型里（连接缩放需要跨栏同步）
    let zoom: CGFloat?
    let onZoomChange: (CGFloat?) -> Void
    /// 连接滚动的目标位置（归一化 0...1）；nil = 未开启同步
    let scrollSync: CGPoint?
    let onScrollChange: (CGPoint) -> Void
    /// 强制刷新：忽略持久化缓存重新下载
    let onRefresh: () -> Void
    let onCopy: () -> Void
    let onSave: () -> Void

    /// fit 模式的实际缩放系数（由内容区几何尺寸算出，供百分比展示与 +/−/pinch 起点用）
    @State private var fittedScale: CGFloat = 1
    /// pinch 手势起点倍率（手势值是相对起点的比例）
    @State private var pinchBaseZoom: CGFloat?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
    }

    private var isImage: Bool {
        if case .image = state { return true }
        return false
    }

    private var isLoading: Bool {
        if case .loading = state { return true }
        return false
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(node.name)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if isImage {
                Button { onZoomChange(effectiveScale / 1.25) } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .accessibilityIdentifier("preview-zoom-out")
                .help("缩小")
                Button { onZoomChange(1) } label: {
                    Text("\(Int((effectiveScale * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .frame(minWidth: 36)
                }
                .accessibilityIdentifier("preview-zoom-reset")
                .help("还原 100%")
                Button { onZoomChange(effectiveScale * 1.25) } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .accessibilityIdentifier("preview-zoom-in")
                .help("放大")
                Button { onZoomChange(nil) } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                }
                .accessibilityIdentifier("preview-zoom-fit")
                .disabled(zoom == nil)
                .help("适应窗口（fit）")
                Divider().frame(height: 12)
            }
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .accessibilityIdentifier("preview-file-refresh")
            .disabled(isLoading)
            .help("强制重新下载并更新缓存")
            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
            }
            .accessibilityIdentifier("preview-copy")
            .disabled(!canExport)
            .help("复制文件到剪贴板（⌘C 复制所有选中文件）")
            Button(action: onSave) {
                Image(systemName: "square.and.arrow.down")
            }
            .accessibilityIdentifier("preview-save")
            .disabled(!canExport)
            .help("下载到本地…")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.5))
    }

    /// 当前实际缩放系数：手动缩放值，fit 模式下为几何算出的适应系数
    private var effectiveScale: CGFloat {
        zoom ?? fittedScale
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let base = pinchBaseZoom ?? effectiveScale
                pinchBaseZoom = base
                onZoomChange(base * value.magnification)
            }
            .onEnded { _ in pinchBaseZoom = nil }
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
            if let zoom {
                // NSScrollView 封装：SwiftUI ScrollView 无法读写连续滚动偏移，连接滚动做不了
                ZoomedImageScrollView(
                    image: image,
                    zoom: zoom,
                    scrollFraction: scrollSync,
                    onScroll: onScrollChange,
                    onZoomChange: onZoomChange
                )
            } else {
                // fit 模式：适应内容区（留 8pt 边距）且从不超过原图尺寸，居中展示
                GeometryReader { geo in
                    let scale = CGFloat(PreviewZoom.fitScale(
                        imageWidth: image.size.width,
                        imageHeight: image.size.height,
                        containerWidth: geo.size.width - 16,
                        containerHeight: geo.size.height - 16
                    ))
                    Image(nsImage: image)
                        .resizable()
                        .frame(
                            width: max(image.size.width, 1) * scale,
                            height: max(image.size.height, 1) * scale
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onChange(of: scale, initial: true) { fittedScale = scale }
                }
                .contentShape(Rectangle())
                .gesture(magnifyGesture)
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

// MARK: - 缩放图像的滚动容器

/// zoom 模式下的图像滚动容器（NSScrollView 封装）。
/// 连接滚动：用户滚动时把位置按可滚动范围归一化上报（onScroll），
/// 外部传入 scrollFraction 时按比例定位——不同尺寸/倍率的图片也能对应同步。
/// pinch 缩放走 NSMagnificationGestureRecognizer（NSScrollView 会吞掉 SwiftUI 手势）
private struct ZoomedImageScrollView: NSViewRepresentable {
    let image: NSImage
    let zoom: CGFloat
    /// 连接滚动的目标位置（归一化 0...1）；nil = 不同步
    let scrollFraction: CGPoint?
    let onScroll: (CGPoint) -> Void
    let onZoomChange: (CGFloat?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.drawsBackground = false
        scrollView.allowsMagnification = false

        let imageView = FlippedImageView()
        imageView.image = image
        imageView.imageScaling = .scaleAxesIndependently
        imageView.frame = NSRect(origin: .zero, size: zoomedSize)
        scrollView.documentView = imageView

        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.boundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        scrollView.addGestureRecognizer(
            NSMagnificationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMagnify(_:)))
        )
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let imageView = scrollView.documentView as? FlippedImageView else { return }
        if imageView.image !== image {
            imageView.image = image
        }
        if imageView.frame.size != zoomedSize {
            // 尺寸变化会连带触发 bounds 通知，标记为程序性滚动避免误上报
            context.coordinator.isProgrammaticScroll = true
            imageView.setFrameSize(zoomedSize)
            context.coordinator.isProgrammaticScroll = false
        }
        if let fraction = scrollFraction {
            context.coordinator.apply(fraction: fraction, to: scrollView)
        }
    }

    private var zoomedSize: NSSize {
        NSSize(width: max(image.size.width, 1) * zoom, height: max(image.size.height, 1) * zoom)
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: ZoomedImageScrollView
        /// 程序性滚动（同步定位/改尺寸）期间抑制 bounds 通知上报，防止反馈环
        var isProgrammaticScroll = false
        private var pinchBaseZoom: CGFloat?

        init(_ parent: ZoomedImageScrollView) {
            self.parent = parent
        }

        @objc func boundsDidChange(_ notification: Notification) {
            guard !isProgrammaticScroll,
                  let clipView = notification.object as? NSClipView,
                  let documentView = clipView.documentView
            else { return }
            let bounds = clipView.bounds
            let fraction = CGPoint(
                x: PreviewZoom.scrollFraction(origin: bounds.origin.x, viewport: bounds.width, document: documentView.frame.width),
                y: PreviewZoom.scrollFraction(origin: bounds.origin.y, viewport: bounds.height, document: documentView.frame.height)
            )
            parent.onScroll(fraction)
        }

        func apply(fraction: CGPoint, to scrollView: NSScrollView) {
            guard let documentView = scrollView.documentView else { return }
            let clipView = scrollView.contentView
            let target = NSPoint(
                x: PreviewZoom.scrollOrigin(fraction: fraction.x, viewport: clipView.bounds.width, document: documentView.frame.width),
                y: PreviewZoom.scrollOrigin(fraction: fraction.y, viewport: clipView.bounds.height, document: documentView.frame.height)
            )
            let current = clipView.bounds.origin
            guard abs(target.x - current.x) > 0.5 || abs(target.y - current.y) > 0.5 else { return }
            isProgrammaticScroll = true
            clipView.scroll(to: target)
            scrollView.reflectScrolledClipView(clipView)
            isProgrammaticScroll = false
        }

        @objc func handleMagnify(_ gesture: NSMagnificationGestureRecognizer) {
            switch gesture.state {
            case .began:
                pinchBaseZoom = parent.zoom
            case .changed:
                let base = pinchBaseZoom ?? parent.zoom
                parent.onZoomChange(base * (1 + gesture.magnification))
            default:
                pinchBaseZoom = nil
            }
        }
    }
}

/// 翻转坐标系的 NSImageView：让滚动原点落在左上角（与阅读习惯一致）
private final class FlippedImageView: NSImageView {
    override var isFlipped: Bool { true }
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
        onClose?()
    }
}
