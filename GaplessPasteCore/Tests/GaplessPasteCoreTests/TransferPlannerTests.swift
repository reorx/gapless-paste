import Foundation
import Testing
@testable import GaplessPasteCore

@Suite("传输计划：内容类型 → 步骤序列（路径 A 目录上传）")
struct TransferPlannerTests {
    @Test("文件引用：上传后远端路径回传本地剪贴板（与平台无关）")
    func fileReferencesPlan() {
        let expected: TransferPlan = .steps([
            .ensureRemoteDirectory,
            .resolveNameCollision,
            .upload,
            .copyRemotePathsToLocalClipboard,
            .notifySuccess,
        ])
        #expect(TransferPlanner.plan(for: .fileReferences([URL(fileURLWithPath: "/tmp/a.png")])) == expected)
        #expect(TransferPlanner.plan(for: .fileReferences([URL(fileURLWithPath: "/tmp/a.png")]), remoteIsDarwin: true) == expected)
        #expect(TransferPlanner.plan(for: .fileReferences([URL(fileURLWithPath: "/tmp/a.png")]), remoteIsDarwin: false) == expected)
    }

    @Test("图像 + 平台未知（探测前，仅用于拒绝判定）：不含注入/降级步骤")
    func imageDataPlanUnknownPlatform() {
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

    @Test("图像 + Darwin：上传成功后注入远端剪贴板（M2），不覆盖本地剪贴板")
    func imageDataPlanDarwin() {
        let plan = TransferPlanner.plan(for: .imageData(Data([1])), remoteIsDarwin: true)
        #expect(plan == .steps([
            .promptImageName,
            .writeImageToTemporaryFile,
            .ensureRemoteDirectory,
            .resolveNameCollision,
            .upload,
            .injectImageIntoRemoteClipboard,
            .notifySuccess,
        ]))
    }

    @Test("图像 + 非 Darwin：自动降级为路径模式（远端路径写回本地剪贴板）")
    func imageDataPlanNonDarwinDegrades() {
        let plan = TransferPlanner.plan(for: .imageData(Data([1])), remoteIsDarwin: false)
        #expect(plan == .steps([
            .promptImageName,
            .writeImageToTemporaryFile,
            .ensureRemoteDirectory,
            .resolveNameCollision,
            .upload,
            .copyRemotePathsToLocalClipboard,
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

@Suite("同步剪贴板计划：内容直通远端剪贴板，不进目录（M2 路径 B）")
struct SyncPlannerTests {
    @Test("图像：写本地临时 PNG → 固定远端临时路径 → 注入远端剪贴板")
    func imageSyncPlan() {
        let plan = TransferPlanner.syncPlan(for: .imageData(Data([1])), remoteIsDarwin: true)
        #expect(plan == .steps([
            .writeImageToTemporaryFile,
            .ensureRemoteTempDirectory,
            .uploadToFixedTempPath,
            .injectImageIntoRemoteClipboard,
            .notifySuccess,
        ]))
    }

    @Test("纯文本：直接 ssh pbcopy 注入，无落盘")
    func textSyncPlan() {
        let plan = TransferPlanner.syncPlan(for: .text("hello"), remoteIsDarwin: true)
        #expect(plan == .steps([
            .injectTextIntoRemoteClipboard,
            .notifySuccess,
        ]))
    }

    @Test("单个图片文件引用：读文件转 PNG 后走图像同步路径（Finder ⌘C 截图文件）")
    func singleImageFileReferenceSyncPlan() {
        let expected: SyncPlan = .steps([
            .convertImageFileToTemporaryPNG,
            .ensureRemoteTempDirectory,
            .uploadToFixedTempPath,
            .injectImageIntoRemoteClipboard,
            .notifySuccess,
        ])
        for name in ["shot.png", "photo.JPG", "pic.jpeg", "x.heic", "y.webp", "z.tiff"] {
            let plan = TransferPlanner.syncPlan(for: .fileReferences([URL(fileURLWithPath: "/tmp/\(name)")]), remoteIsDarwin: true)
            #expect(plan == expected, "\(name) 应按图像同步")
        }
    }

    @Test("非图片文件 / 多个文件引用不支持同步（提示改用目录上传）")
    func nonImageOrMultipleFileReferencesRejected() {
        let pdf = URL(fileURLWithPath: "/tmp/a.pdf")
        let noExtension = URL(fileURLWithPath: "/tmp/a")
        let pngA = URL(fileURLWithPath: "/tmp/a.png")
        let pngB = URL(fileURLWithPath: "/tmp/b.png")
        #expect(TransferPlanner.syncPlan(for: .fileReferences([pdf]), remoteIsDarwin: true) == .rejected(.fileReferencesNotSyncable))
        #expect(TransferPlanner.syncPlan(for: .fileReferences([noExtension]), remoteIsDarwin: true) == .rejected(.fileReferencesNotSyncable))
        #expect(TransferPlanner.syncPlan(for: .fileReferences([pngA, pngB]), remoteIsDarwin: true) == .rejected(.fileReferencesNotSyncable))
    }

    @Test("图片文件引用 + 非 Darwin 远端：拒绝注入")
    func imageFileReferenceNonDarwinRejected() {
        let plan = TransferPlanner.syncPlan(for: .fileReferences([URL(fileURLWithPath: "/tmp/a.png")]), remoteIsDarwin: false)
        #expect(plan == .rejected(.remoteClipboardUnsupported))
    }

    @Test("平台无关的内容拒绝判定（app 在 ssh 探测前先行调用）")
    func contentRejectionBeforeProbe() {
        #expect(TransferPlanner.contentRejection(forSync: .empty) == .emptyClipboard)
        #expect(TransferPlanner.contentRejection(forSync: .fileReferences([URL(fileURLWithPath: "/tmp/a.pdf")])) == .fileReferencesNotSyncable)
        #expect(TransferPlanner.contentRejection(forSync: .fileReferences([URL(fileURLWithPath: "/tmp/a.png")])) == nil)
        #expect(TransferPlanner.contentRejection(forSync: .imageData(Data([1]))) == nil)
        #expect(TransferPlanner.contentRejection(forSync: .text("hi")) == nil)
    }

    @Test("空剪贴板拒绝")
    func emptyRejected() {
        #expect(TransferPlanner.syncPlan(for: .empty, remoteIsDarwin: true) == .rejected(.emptyClipboard))
    }

    @Test("非 Darwin 远端：同步语义不成立，直接拒绝")
    func nonDarwinRejected() {
        #expect(TransferPlanner.syncPlan(for: .text("hi"), remoteIsDarwin: false) == .rejected(.remoteClipboardUnsupported))
        #expect(TransferPlanner.syncPlan(for: .imageData(Data([1])), remoteIsDarwin: false) == .rejected(.remoteClipboardUnsupported))
    }

    @Test("拒绝提示文案")
    func rejectionMessages() {
        #expect(SyncRejection.fileReferencesNotSyncable.userMessage.contains("目录上传"))
        #expect(!SyncRejection.emptyClipboard.userMessage.isEmpty)
        #expect(!SyncRejection.remoteClipboardUnsupported.userMessage.isEmpty)
    }
}
