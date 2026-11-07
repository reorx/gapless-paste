import Testing
@testable import GaplessPasteCore

struct PreviewTextFontSizeTests {
    @Test func previewStartsAtTwelvePointsWithOnePointSteps() {
        #expect(PreviewTextFontSize.defaultValue == 12)
        #expect(PreviewTextFontSize.range == 8.0...32.0)
        #expect(PreviewTextFontSize.step == 1)
    }

    @Test(arguments: [8.0, 12, 20, 32, 15.5])
    func validStoredSizesArePreserved(_ value: Double) {
        #expect(PreviewTextFontSize.normalize(value) == value)
    }

    @Test func outOfRangeStoredSizesUseNearestBoundary() {
        #expect(PreviewTextFontSize.normalize(-100) == 8)
        #expect(PreviewTextFontSize.normalize(100) == 32)
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity])
    func nonFiniteStoredSizesUseDefault(_ value: Double) {
        #expect(PreviewTextFontSize.normalize(value) == 12)
    }
}
