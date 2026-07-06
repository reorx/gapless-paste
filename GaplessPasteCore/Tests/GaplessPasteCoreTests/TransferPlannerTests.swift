import Foundation
import Testing
@testable import GaplessPasteCore

@Suite("传输计划：内容类型 → 步骤序列（M1 路径 A）")
struct TransferPlannerTests {
    @Test("文件引用：上传后远端路径回传本地剪贴板")
    func fileReferencesPlan() {
        let plan = TransferPlanner.plan(for: .fileReferences([URL(fileURLWithPath: "/tmp/a.png")]))
        #expect(plan == .steps([
            .ensureRemoteDirectory,
            .resolveNameCollision,
            .upload,
            .copyRemotePathsToLocalClipboard,
            .notifySuccess,
        ]))
    }

    @Test("图像数据：先弹重命名浮窗，不覆盖本地剪贴板")
    func imageDataPlan() {
        let plan = TransferPlanner.plan(for: .imageData(Data([1])))
        #expect(plan == .steps([
            .promptImageName,
            .writeImageToTemporaryFile,
            .ensureRemoteDirectory,
            .resolveNameCollision,
            .upload,
            .notifySuccess,
        ]))
    }

    @Test("纯文本不支持目录上传")
    func textRejected() {
        #expect(TransferPlanner.plan(for: .text("hello")) == .rejected(.unsupportedText))
    }

    @Test("空剪贴板拒绝")
    func emptyRejected() {
        #expect(TransferPlanner.plan(for: .empty) == .rejected(.emptyClipboard))
    }
}
