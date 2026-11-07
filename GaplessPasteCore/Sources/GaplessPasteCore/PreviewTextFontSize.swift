/// 文本预览的本机显示规则；兼容手动修改或旧版本留下的持久化数值。
public enum PreviewTextFontSize {
    public static let defaultValue: Double = 12
    public static let range: ClosedRange<Double> = 8...32
    public static let step: Double = 1

    public static func normalize(_ value: Double) -> Double {
        guard value.isFinite else { return defaultValue }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
