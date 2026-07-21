import Foundation
import Testing
@testable import GaplessPasteCore

// 图像预览缩放：fit 模式缩放系数（适应容器但从不放大超过 100%）+ 倍率钳制

struct PreviewZoomTests {
    // MARK: - fitScale

    @Test func largeImageScalesDownToFitContainer() {
        // 2000×1000 图放进 500×500 容器：受宽度约束 → 0.25
        let scale = PreviewZoom.fitScale(imageWidth: 2000, imageHeight: 1000, containerWidth: 500, containerHeight: 500)
        #expect(scale == 0.25)
    }

    @Test func heightConstrainedImageUsesHeightRatio() {
        // 1000×2000 图放进 500×500 容器：受高度约束 → 0.25
        let scale = PreviewZoom.fitScale(imageWidth: 1000, imageHeight: 2000, containerWidth: 500, containerHeight: 500)
        #expect(scale == 0.25)
    }

    @Test func smallImageNeverUpscalesBeyondOriginalSize() {
        // 100×100 图放进 800×600 容器：不放大 → 1.0
        let scale = PreviewZoom.fitScale(imageWidth: 100, imageHeight: 100, containerWidth: 800, containerHeight: 600)
        #expect(scale == 1.0)
    }

    @Test func degenerateSizesFallBackToOriginalScale() {
        #expect(PreviewZoom.fitScale(imageWidth: 0, imageHeight: 100, containerWidth: 500, containerHeight: 500) == 1.0)
        #expect(PreviewZoom.fitScale(imageWidth: 100, imageHeight: 100, containerWidth: 0, containerHeight: 500) == 1.0)
    }

    // MARK: - clamp

    @Test func clampKeepsZoomWithinRange() {
        #expect(PreviewZoom.clamp(0.01) == PreviewZoom.range.lowerBound)
        #expect(PreviewZoom.clamp(100) == PreviewZoom.range.upperBound)
        #expect(PreviewZoom.clamp(1.5) == 1.5)
    }

    // MARK: - 滚动位置 ⇄ 归一化比例（连接滚动跨分栏同步用）

    @Test func scrollFractionIsRatioOfScrollableRange() {
        // 文档 1000，视口 400 → 可滚动 600；origin 300 → 0.5
        #expect(PreviewZoom.scrollFraction(origin: 300, viewport: 400, document: 1000) == 0.5)
        #expect(PreviewZoom.scrollFraction(origin: 0, viewport: 400, document: 1000) == 0)
        #expect(PreviewZoom.scrollFraction(origin: 600, viewport: 400, document: 1000) == 1)
    }

    @Test func scrollFractionIsZeroWhenDocumentFitsViewport() {
        #expect(PreviewZoom.scrollFraction(origin: 0, viewport: 500, document: 300) == 0)
        #expect(PreviewZoom.scrollFraction(origin: 10, viewport: 500, document: 500) == 0)
    }

    @Test func scrollFractionClampsOverscroll() {
        // 弹性滚动可能越界，比例钳制在 0...1
        #expect(PreviewZoom.scrollFraction(origin: -50, viewport: 400, document: 1000) == 0)
        #expect(PreviewZoom.scrollFraction(origin: 700, viewport: 400, document: 1000) == 1)
    }

    @Test func scrollOriginMapsFractionBackToOffset() {
        #expect(PreviewZoom.scrollOrigin(fraction: 0.5, viewport: 400, document: 1000) == 300)
        #expect(PreviewZoom.scrollOrigin(fraction: 0, viewport: 400, document: 1000) == 0)
        #expect(PreviewZoom.scrollOrigin(fraction: 1, viewport: 400, document: 1000) == 600)
    }

    @Test func scrollOriginIsZeroWhenNothingToScroll() {
        #expect(PreviewZoom.scrollOrigin(fraction: 0.8, viewport: 500, document: 300) == 0)
    }

    @Test func scrollOriginClampsFraction() {
        #expect(PreviewZoom.scrollOrigin(fraction: 1.5, viewport: 400, document: 1000) == 600)
        #expect(PreviewZoom.scrollOrigin(fraction: -0.5, viewport: 400, document: 1000) == 0)
    }
}
