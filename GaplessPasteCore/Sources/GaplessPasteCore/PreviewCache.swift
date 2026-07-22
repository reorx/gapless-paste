import Foundation
import CryptoKit

// 持久化预览缓存的路径映射（纯逻辑）。
// 缓存根目录由 app 侧决定（~/Library/Caches/GaplessPaste/preview/），
// 这里只负责把 机器-远端文件路径 映射为稳定的相对路径：
//   <alias 安全化>/<完整远端路径 SHA256 前 16 位>/<原始文件名>
// - 散列完整路径 → 不同目录的同名文件绝不冲突，且映射跨会话稳定
// - 末段保留原始文件名 → 复制/下载导出时保留原名
public enum PreviewCache {
    public static func relativePath(sshAlias: String, remotePath: String) -> String {
        let digest = SHA256.hash(data: Data(remotePath.utf8))
        let hash = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        let fileName = sanitizeSegment((remotePath as NSString).lastPathComponent)
        return "\(sanitizeSegment(sshAlias))/\(hash)/\(fileName)"
    }

    /// 单段文件系统安全化：替换路径分隔符与冒号（HFS 遗留），拒绝 . / .. / 空段
    private static func sanitizeSegment(_ segment: String) -> String {
        let cleaned = segment
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        if cleaned.isEmpty || cleaned == "." || cleaned == ".." {
            return "_"
        }
        return cleaned
    }
}
