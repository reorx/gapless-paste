import Foundation

// 菜单/通知里的人类可读格式：字节数（B/KB/MB/GB）与相对时间（10s前、5分钟前）

public enum DisplayFormatter {
    /// 1024 进制，KB 及以上保留一位小数（整数值去掉 .0）
    public static func byteCountText(_ bytes: Int) -> String {
        guard bytes >= 1024 else { return "\(bytes) B" }
        var value = Double(bytes)
        for unit in ["KB", "MB", "GB", "TB"] {
            value /= 1024
            if value < 1024 || unit == "TB" {
                let rounded = (value * 10).rounded() / 10
                let text = rounded == rounded.rounded()
                    ? String(Int(rounded))
                    : String(format: "%.1f", rounded)
                return "\(text) \(unit)"
            }
        }
        fatalError("unreachable")
    }

    /// 相对时间：<1s（含时钟回拨）→ 刚刚；秒 → Ns前；再往上分钟/小时/天
    public static func relativeTimeText(from past: Date, to now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(past))
        switch seconds {
        case ..<1: return "刚刚"
        case ..<60: return "\(seconds)s前"
        case ..<3600: return "\(seconds / 60)分钟前"
        case ..<86_400: return "\(seconds / 3600)小时前"
        default: return "\(seconds / 86_400)天前"
        }
    }
}
