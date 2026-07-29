import Foundation

// (内容类型, 目标) → 步骤序列。app 侧的 AppState 按序解释执行。
// 路径 A（目录上传）：M2 起图像按远端平台分支——Darwin 上传后注入远端剪贴板，
// 非 Darwin 自动降级为路径模式（远端路径写回本地剪贴板）。
// 路径 B（同步剪贴板）：内容直通远端剪贴板，不进目录，仅 Darwin 支持。

public enum TransferStep: Equatable, Sendable {
    case promptImageName
    case writeImageToTemporaryFile
    case ensureRemoteDirectory
    case resolveNameCollision
    case upload
    case injectImageIntoRemoteClipboard
    case copyRemotePathsToLocalClipboard
    case notifySuccess
}

public enum TransferRejection: Equatable, Sendable {
    case emptyClipboard
    case unsupportedText

    public var userMessage: String {
        switch self {
        case .emptyClipboard:
            return "剪贴板没有可上传的内容"
        case .unsupportedText:
            return "剪贴板中是文本，目录上传不适用（请用「同步到远端剪贴板 →」）"
        }
    }
}

public enum TransferPlan: Equatable, Sendable {
    case steps([TransferStep])
    case rejected(TransferRejection)
}

// MARK: - 同步剪贴板（路径 B）

public enum SyncStep: Equatable, Sendable {
    case writeImageToTemporaryFile
    case convertImageFileToTemporaryPNG
    case ensureRemoteTempDirectory
    case uploadToFixedTempPath
    case injectImageIntoRemoteClipboard
    case injectTextIntoRemoteClipboard
    case notifySuccess
}

public enum SyncRejection: Equatable, Sendable {
    case emptyClipboard
    case fileReferencesNotSyncable
    case remoteClipboardUnsupported

    public var userMessage: String {
        switch self {
        case .emptyClipboard:
            return "剪贴板没有可同步的内容"
        case .fileReferencesNotSyncable:
            return "只有单个图片文件支持同步剪贴板，其余请改用目录上传"
        case .remoteClipboardUnsupported:
            return "远端不是 macOS，不支持剪贴板注入"
        }
    }
}

public enum SyncPlan: Equatable, Sendable {
    case steps([SyncStep])
    case rejected(SyncRejection)
}

public enum TransferPlanner {
    /// remoteIsDarwin 为 nil = 尚未探测（app 在探测前仅用返回值做拒绝判定）；
    /// 探测后按平台决定图像上传的收尾步骤
    public static func plan(for content: ClassifiedContent, remoteIsDarwin: Bool? = nil) -> TransferPlan {
        switch content {
        case .fileReferences:
            // 文件引用：按原名上传，远端绝对路径回传本地剪贴板（与平台无关）
            return .steps([
                .ensureRemoteDirectory,
                .resolveNameCollision,
                .upload,
                .copyRemotePathsToLocalClipboard,
                .notifySuccess,
            ])
        case .imageData:
            // 图像：重命名浮窗 → 上传；不覆盖本地剪贴板（图像保留在本地）。
            // Darwin 注入远端剪贴板；非 Darwin 降级为路径模式
            var steps: [TransferStep] = [
                .promptImageName,
                .writeImageToTemporaryFile,
                .ensureRemoteDirectory,
                .resolveNameCollision,
                .upload,
            ]
            switch remoteIsDarwin {
            case true?: steps.append(.injectImageIntoRemoteClipboard)
            case false?: steps.append(.copyRemotePathsToLocalClipboard)
            case nil: break
            }
            steps.append(.notifySuccess)
            return .steps(steps)
        case .text:
            return .rejected(.unsupportedText)
        case .empty:
            return .rejected(.emptyClipboard)
        }
    }

    /// 与平台无关的同步内容拒绝判定（app 在 ssh 探测前先行调用）；nil = 内容可同步。
    /// 文件引用仅支持单个图片文件（读文件转 PNG 后走图像路径），其余仍走目录上传
    public static func contentRejection(forSync content: ClassifiedContent) -> SyncRejection? {
        switch content {
        case .empty:
            return .emptyClipboard
        case .fileReferences(let urls):
            guard urls.count == 1, PasteboardClassifier.isImageFileURL(urls[0]) else {
                return .fileReferencesNotSyncable
            }
            return nil
        case .imageData, .text:
            return nil
        }
    }

    /// 「⇄ 同步剪贴板」：最快路径，无重命名浮窗、无目录选择
    public static func syncPlan(for content: ClassifiedContent, remoteIsDarwin: Bool) -> SyncPlan {
        if let rejection = contentRejection(forSync: content) {
            return .rejected(rejection)
        }
        guard remoteIsDarwin else {
            return .rejected(.remoteClipboardUnsupported)
        }
        switch content {
        case .fileReferences:
            // 单个图片文件（contentRejection 已保证）：读文件转 PNG，其后与图像数据同路径
            return .steps([
                .convertImageFileToTemporaryPNG,
                .ensureRemoteTempDirectory,
                .uploadToFixedTempPath,
                .injectImageIntoRemoteClipboard,
                .notifySuccess,
            ])
        case .imageData:
            // 图像走固定远端临时路径（每次覆盖），再注入远端剪贴板
            return .steps([
                .writeImageToTemporaryFile,
                .ensureRemoteTempDirectory,
                .uploadToFixedTempPath,
                .injectImageIntoRemoteClipboard,
                .notifySuccess,
            ])
        case .text:
            // 纯文本直接 ssh pbcopy，无落盘
            return .steps([
                .injectTextIntoRemoteClipboard,
                .notifySuccess,
            ])
        case .empty:
            return .rejected(.emptyClipboard)
        }
    }
}
