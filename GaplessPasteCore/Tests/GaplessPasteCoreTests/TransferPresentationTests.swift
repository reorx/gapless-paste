import Foundation
import Testing
@testable import GaplessPasteCore

@Suite("传输展示：记录与短暂反馈分离")
struct TransferPresentationTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    func record(_ operation: TransferRecord.Operation = .upload, content: TransferContent = .init(kind: .image)) -> TransferRecord {
        TransferRecord(operation: operation, machine: "mini", directory: "inbox", content: content, startedAt: now)
    }

    @Test("首次启动没有伪造记录；上传/同步/接收立即显示正确方向")
    func emptyAndDirections() {
        var state = TransferPresentation()
        #expect(state.record == nil)
        #expect(state.title == "还没有传输记录")
        #expect(state.feedback == .idle)
        for operation in [TransferRecord.Operation.upload, .pushClipboard, .pullClipboard] {
            let item = record(operation)
            state.begin(item)
            #expect(state.isBusy)
            #expect(state.feedback == (operation == .pullClipboard ? .receiving : .sending))
            #expect(!state.shouldAnimate(at: now.addingTimeInterval(0.29), reduceMotion: false))
            #expect(state.shouldAnimate(at: now.addingTimeInterval(0.3), reduceMotion: false))
            #expect(!state.shouldAnimate(at: now.addingTimeInterval(1), reduceMotion: true))
            state.abandon(id: item.id)
        }
    }

    @Test("摘要不带长文件名或错误正文；多文件只显示数量，无手工缩进")
    func boundedSummary() {
        let names = [String(repeating: "超长文件名", count: 80) + ".png", "second.pdf"]
        var state = TransferPresentation()
        let item = record(content: .init(kind: .files, fileNames: names, byteCount: 1234))
        state.begin(item)
        state.finish(id: item.id, outcome: .success, at: now)
        #expect(state.title == "已上传到远端")
        #expect(state.record?.content.label == "2 个文件")
        #expect(state.subtitle(at: now) == "2 个文件 · 本机 → mini · 刚刚")
        #expect(!state.subtitle(at: now).contains(names[0]))
        let error = String(repeating: "permission denied ", count: 100)
        let failed = record()
        state.begin(failed)
        state.finish(id: failed.id, outcome: .failure, at: now, message: error)
        #expect(state.title == "上传失败")
        #expect(!state.subtitle(at: now).contains(error))
        #expect(state.record?.message == error)
    }

    @Test("成功两秒后只移除徽标，记录与完整元数据保留")
    func successExpiry() {
        var state = TransferPresentation()
        let item = record(.pushClipboard, content: .init(kind: .text, characterCount: 42))
        state.begin(item)
        state.finish(id: item.id, outcome: .success, at: now)
        state.expireSuccess(id: item.id, at: now.addingTimeInterval(1.99))
        #expect(state.feedback == .success)
        state.expireSuccess(id: item.id, at: now.addingTimeInterval(2))
        #expect(state.feedback == .idle)
        #expect(state.record?.content.characterCount == 42)
        #expect(state.title == "已同步到远端")
        #expect(!state.isBusy)
    }

    @Test("旧超时、完成和失败确认都不能覆盖新操作")
    func staleEvents() {
        var state = TransferPresentation()
        let old = record()
        state.begin(old)
        state.finish(id: old.id, outcome: .success, at: now)
        let next = record(.pullClipboard)
        state.begin(next)
        state.expireSuccess(id: old.id, at: now.addingTimeInterval(3))
        state.acknowledge(id: old.id)
        state.finish(id: old.id, outcome: .failure, at: now)
        #expect(state.record?.id == next.id)
        #expect(state.feedback == .receiving)
        #expect(state.isBusy)
    }

    @Test("失败停止动画并持续提醒，查看对应详情才解除，记录保留")
    func failureAcknowledgement() {
        var state = TransferPresentation()
        let item = record(.pullClipboard)
        state.begin(item)
        state.finish(id: item.id, outcome: .failure, at: now, message: "SSH timeout")
        state.expireSuccess(id: item.id, at: now.addingTimeInterval(100))
        #expect(state.feedback == .attention)
        #expect(!state.shouldAnimate(at: now.addingTimeInterval(100), reduceMotion: false))
        state.acknowledge(id: UUID())
        #expect(state.feedback == .attention)
        state.acknowledge(id: item.id)
        #expect(state.feedback == .idle)
        #expect(state.record?.outcome == .failure)
    }

    @Test("接收后补齐内容；没有源文件名时不虚构名称或存储正文")
    func receivedMetadata() {
        var state = TransferPresentation()
        let item = record(.pullClipboard, content: .init(kind: .clipboard))
        state.begin(item)
        #expect(state.subtitle(at: now) == "剪贴板 · mini → 本机")
        state.updateContent(id: item.id, content: .init(kind: .text, characterCount: 300))
        state.finish(id: item.id, outcome: .success, at: now)
        #expect(state.record?.content.fileNames.isEmpty == true)
        #expect(state.title == "已接收到本机")
        #expect(state.subtitle(at: now) == "文本 · mini → 本机 · 刚刚")
    }

    @Test("取消、空远端和平台拒绝退出 busy，恢复此前记录且不显示成功")
    func abandonedOperations() {
        var state = TransferPresentation()
        let first = record()
        state.begin(first)
        state.abandon(id: first.id)
        #expect(state.record == nil)
        #expect(state.feedback == .idle)
        state.begin(first)
        state.finish(id: first.id, outcome: .failure, at: now)
        let rejected = record(.pullClipboard)
        state.begin(rejected)
        state.abandon(id: rejected.id)
        #expect(state.record?.id == first.id)
        #expect(state.record?.outcome == .failure)
        #expect(!state.isBusy)
        #expect(state.feedback == .idle)
    }

    @Test("文件落盘后注入失败是部分成功，保留路径且不能作为上传失败重传")
    func partialSuccess() {
        var state = TransferPresentation()
        let item = record()
        state.begin(item)
        state.finish(id: item.id, outcome: .partialSuccess, at: now, message: "pbcopy failed", remotePaths: ["/tmp/shot.png"])
        #expect(state.title == "已上传，剪贴板写入失败")
        #expect(state.record?.remotePaths == ["/tmp/shot.png"])
        #expect(state.record?.outcome != .failure)
        #expect(state.feedback == .attention)
        #expect(!state.isBusy)
    }
}
