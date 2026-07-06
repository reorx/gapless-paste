import Foundation

// (内容类型, 目标) → 步骤序列。app 侧的 AppState 按序解释执行。
// M1 只有路径 A（目录上传）；M2 扩展远端剪贴板注入与平台降级分支。

public enum TransferStep: Equatable, Sendable {
    case promptImageName
    case writeImageToTemporaryFile
    case ensureRemoteDirectory
    case resolveNameCollision
    case upload
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
            return "剪贴板中是文本，目录上传不适用（请等 M2 的「同步剪贴板」）"
        }
    }
}

public enum TransferPlan: Equatable, Sendable {
    case steps([TransferStep])
    case rejected(TransferRejection)
}

public enum TransferPlanner {
    public static func plan(for content: ClassifiedContent) -> TransferPlan {
        switch content {
        case .fileReferences:
            // 文件引用：按原名上传，远端绝对路径回传本地剪贴板
            return .steps([
                .ensureRemoteDirectory,
                .resolveNameCollision,
                .upload,
                .copyRemotePathsToLocalClipboard,
                .notifySuccess,
            ])
        case .imageData:
            // 图像：重命名浮窗 → 上传；M1 不覆盖本地剪贴板（图像保留在本地）
            return .steps([
                .promptImageName,
                .writeImageToTemporaryFile,
                .ensureRemoteDirectory,
                .resolveNameCollision,
                .upload,
                .notifySuccess,
            ])
        case .text:
            return .rejected(.unsupportedText)
        case .empty:
            return .rejected(.emptyClipboard)
        }
    }
}
