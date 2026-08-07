import Foundation
import Testing
@testable import GaplessPasteCore

@Suite("展示格式化：字节数、相对时间、音频时长")
struct DisplayFormatterTests {
    @Test("音频时长：分:秒，秒补零，不足 1 分钟显示 0:SS")
    func durationMinutesSeconds() {
        #expect(DisplayFormatter.durationText(0) == "0:00")
        #expect(DisplayFormatter.durationText(4.9) == "0:04") // 播放器惯例向下取整
        #expect(DisplayFormatter.durationText(65) == "1:05")
        #expect(DisplayFormatter.durationText(3599) == "59:59")
    }

    @Test("音频时长：≥1 小时显示 时:分:秒")
    func durationHours() {
        #expect(DisplayFormatter.durationText(3600) == "1:00:00")
        #expect(DisplayFormatter.durationText(3723) == "1:02:03")
    }

    @Test("音频时长：NaN/无穷/负值兜底 0:00")
    func durationInvalidValues() {
        #expect(DisplayFormatter.durationText(.nan) == "0:00")
        #expect(DisplayFormatter.durationText(.infinity) == "0:00")
        #expect(DisplayFormatter.durationText(-5) == "0:00")
    }

    @Test("字节数 <1024 显示为 B")
    func byteCountBytes() {
        #expect(DisplayFormatter.byteCountText(0) == "0 B")
        #expect(DisplayFormatter.byteCountText(512) == "512 B")
        #expect(DisplayFormatter.byteCountText(1023) == "1023 B")
    }

    @Test("字节数 KB：一位小数，整数值去掉 .0")
    func byteCountKB() {
        #expect(DisplayFormatter.byteCountText(1024) == "1 KB")
        #expect(DisplayFormatter.byteCountText(1536) == "1.5 KB")
        #expect(DisplayFormatter.byteCountText(269_060) == "262.8 KB")
    }

    @Test("字节数 MB / GB")
    func byteCountMBGB() {
        #expect(DisplayFormatter.byteCountText(1_048_576) == "1 MB")
        #expect(DisplayFormatter.byteCountText(2_621_440) == "2.5 MB")
        #expect(DisplayFormatter.byteCountText(1_073_741_824) == "1 GB")
    }

    @Test("相对时间：不足 1 秒为「刚刚」，负值（时钟回拨）同样兜底")
    func relativeJustNow() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(DisplayFormatter.relativeTimeText(from: now.addingTimeInterval(-0.4), to: now) == "刚刚")
        #expect(DisplayFormatter.relativeTimeText(from: now.addingTimeInterval(5), to: now) == "刚刚")
    }

    @Test("相对时间：秒级 Ns前")
    func relativeSeconds() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(DisplayFormatter.relativeTimeText(from: now.addingTimeInterval(-10), to: now) == "10s前")
        #expect(DisplayFormatter.relativeTimeText(from: now.addingTimeInterval(-59), to: now) == "59s前")
    }

    @Test("相对时间：分钟级 N分钟前")
    func relativeMinutes() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(DisplayFormatter.relativeTimeText(from: now.addingTimeInterval(-60), to: now) == "1分钟前")
        #expect(DisplayFormatter.relativeTimeText(from: now.addingTimeInterval(-300), to: now) == "5分钟前")
        #expect(DisplayFormatter.relativeTimeText(from: now.addingTimeInterval(-3599), to: now) == "59分钟前")
    }

    @Test("相对时间：小时级与天级")
    func relativeHoursDays() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(DisplayFormatter.relativeTimeText(from: now.addingTimeInterval(-3600), to: now) == "1小时前")
        #expect(DisplayFormatter.relativeTimeText(from: now.addingTimeInterval(-86_399), to: now) == "23小时前")
        #expect(DisplayFormatter.relativeTimeText(from: now.addingTimeInterval(-86_400), to: now) == "1天前")
        #expect(DisplayFormatter.relativeTimeText(from: now.addingTimeInterval(-3 * 86_400), to: now) == "3天前")
    }
}
