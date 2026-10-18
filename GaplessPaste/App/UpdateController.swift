import AppKit
import Sparkle

/// App 层拥有 Sparkle；Core 保持与 UI、更新框架无关。
@MainActor
final class UpdateController: NSObject, SPUUpdaterDelegate {
    private(set) var controller: SPUStandardUpdaterController!

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    #if DEBUG
    // 即使用户偏好曾在正式版启用自动检查，Debug 也只接受手动检查。
    // 不改 Sparkle 的持久偏好，避免影响同 bundle ID 的正式版。
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard updateCheck == .updates else {
            throw NSError(
                domain: "com.reorx.gaplesspaste.updater", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Debug 构建仅支持手动检查更新"]
            )
        }
    }
    #endif
}
