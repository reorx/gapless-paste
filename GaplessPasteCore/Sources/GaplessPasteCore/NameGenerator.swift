import Foundation

// 命名三件事：默认图像名（Date 注入可测）、清洗、重名后缀

public enum NameGenerator {
    /// 图像默认名：shot-YYYYMMDD-HHmmss.png（本地时间）
    public static func defaultImageName(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "shot-\(formatter.string(from: date)).png"
    }

    /// 清洗规则：/、:、空白、控制字符替换为 -（避免远端路径含空格给 Claude Code 引用添乱）
    public static func sanitize(_ name: String) -> String {
        let sanitized = String(name.map { char -> Character in
            if char == "/" || char == ":" { return "-" }
            if let scalar = char.unicodeScalars.first,
               char.unicodeScalars.count == 1,
               CharacterSet.whitespacesAndNewlines.contains(scalar) || CharacterSet.controlCharacters.contains(scalar) {
                return "-"
            }
            return char
        })
        // 全被清成 - 或输入为空时回落，避免产生无意义文件名
        if sanitized.allSatisfy({ $0 == "-" }) {
            return "untitled"
        }
        return sanitized
    }

    /// 重名后缀插入在扩展名之前：shot.png + 1 → shot-1.png；点开头的隐藏文件视为无扩展名
    public static func appendingSuffix(_ name: String, index: Int) -> String {
        guard let dotIndex = name.lastIndex(of: "."), dotIndex != name.startIndex else {
            return "\(name)-\(index)"
        }
        let stem = name[name.startIndex..<dotIndex]
        let ext = name[dotIndex...]
        return "\(stem)-\(index)\(ext)"
    }

    /// 从原名开始探测，存在则 -1、-2 递增直到可用
    public static func firstAvailable(_ name: String, exists: (String) throws -> Bool) rethrows -> String {
        var candidate = name
        var index = 0
        while try exists(candidate) {
            index += 1
            candidate = appendingSuffix(name, index: index)
        }
        return candidate
    }
}
