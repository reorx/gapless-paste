import Foundation

/// 图像预览缩放的纯计算：fit 模式系数与手动倍率钳制
public enum PreviewZoom {
    /// 手动缩放倍率范围（1 = 原始尺寸）
    public static let range: ClosedRange<Double> = 0.1...8

    public static func clamp(_ value: Double) -> Double {
        min(range.upperBound, max(range.lowerBound, value))
    }

    /// fit 模式缩放系数：图像等比缩小到容器内，但从不放大超过原始尺寸（上限 1.0）。
    /// 尺寸非法（任一边 ≤ 0）时回落 1.0
    public static func fitScale(imageWidth: Double, imageHeight: Double, containerWidth: Double, containerHeight: Double) -> Double {
        guard imageWidth > 0, imageHeight > 0, containerWidth > 0, containerHeight > 0 else { return 1.0 }
        return min(1.0, containerWidth / imageWidth, containerHeight / imageHeight)
    }

    // MARK: - 连接滚动：滚动偏移 ⇄ 归一化比例（单轴，双轴各调一次）

    /// 滚动偏移 → 归一化比例（0...1，弹性越界钳制）。文档不超出视口时恒为 0
    public static func scrollFraction(origin: Double, viewport: Double, document: Double) -> Double {
        let scrollable = document - viewport
        guard scrollable > 0 else { return 0 }
        return min(1, max(0, origin / scrollable))
    }

    /// 归一化比例 → 滚动偏移（比例先钳制到 0...1）。文档不超出视口时恒为 0
    public static func scrollOrigin(fraction: Double, viewport: Double, document: Double) -> Double {
        let scrollable = document - viewport
        guard scrollable > 0 else { return 0 }
        return min(1, max(0, fraction)) * scrollable
    }
}
