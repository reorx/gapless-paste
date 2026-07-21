import Foundation

/// 近期使用过的路径列表（预览远端目录的输入历史）：最新在前、去重、上限裁剪
public enum RecentPaths {
    public static let defaultLimit = 8

    /// 把 `path`（先 trim 空白）置顶插入 `existing`：已存在则上移，超过 `limit` 丢弃最旧项。
    /// 空白路径不入列，原列表原样返回
    public static func updated(_ existing: [String], adding path: String, limit: Int = defaultLimit) -> [String] {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return existing }
        var result = existing.filter { $0 != trimmed }
        result.insert(trimmed, at: 0)
        return Array(result.prefix(limit))
    }
}
