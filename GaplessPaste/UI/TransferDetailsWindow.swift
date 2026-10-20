import AppKit
import SwiftUI
import GaplessPasteCore

@MainActor
final class TransferDetailsWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    init(record: TransferRecord) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
        )
        window.title = record.needsAttention ? "失败详情 — GaplessPaste" : "传输详情 — GaplessPaste"
        window.contentView = NSHostingView(rootView: TransferDetailsView(record: record))
        window.minSize = NSSize(width: 420, height: 300)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    func show() {
        guard let window else { return }
        DockPresence.track(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) { onClose?() }
}

/// 值类型快照：新的传输不会改掉用户正在阅读的结果。
private struct TransferDetailsView: View {
    let record: TransferRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(record.title)
                    .font(.title2.weight(.semibold))
                    .accessibilityIdentifier("transfer-detail-result")
                VStack(alignment: .leading, spacing: 10) {
                    field("方向", record.direction)
                    if let directory = record.directory { field("目标目录", directory) }
                    field("内容", record.content.label)
                    if let bytes = record.content.byteCount { field("大小", DisplayFormatter.byteCountText(bytes)) }
                    if let count = record.content.characterCount { field("字数", "\(count) 字符") }
                    field("开始时间", record.startedAt.formatted(date: .numeric, time: .standard))
                    if let finished = record.finishedAt { field("完成时间", finished.formatted(date: .numeric, time: .standard)) }
                }
                if !record.content.fileNames.isEmpty {
                    section("文件名", record.content.fileNames.joined(separator: "\n"))
                }
                if !record.remotePaths.isEmpty {
                    section("远端路径", record.remotePaths.joined(separator: "\n"))
                }
                if let message = record.message {
                    section(record.outcome == .partialSuccess ? "剪贴板写入失败原因" : "失败原因", message)
                }
                if record.outcome == .partialSuccess {
                    Text("文件已上传，可从菜单拷贝远端路径。为避免生成重复文件，此操作不提供重新上传。")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .textSelection(.enabled)
        .accessibilityIdentifier("transfer-detail-content")
    }

    private func field(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label).foregroundStyle(.secondary).frame(width: 62, alignment: .leading)
            Text(value).frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
