import Foundation
import Testing
@testable import GaplessPasteCore

// 近期预览路径列表：新路径置顶、去重上移、裁剪上限、空白忽略

struct RecentPathsTests {
    @Test func addingNewPathPrependsToFront() {
        let updated = RecentPaths.updated(["~/a", "~/b"], adding: "~/c")
        #expect(updated == ["~/c", "~/a", "~/b"])
    }

    @Test func addingExistingPathMovesItToFront() {
        let updated = RecentPaths.updated(["~/a", "~/b", "~/c"], adding: "~/b")
        #expect(updated == ["~/b", "~/a", "~/c"])
    }

    @Test func addingTrimsWhitespaceBeforeComparing() {
        let updated = RecentPaths.updated(["~/a"], adding: "  ~/a  ")
        #expect(updated == ["~/a"])
    }

    @Test func addingEmptyOrBlankPathKeepsListUnchanged() {
        #expect(RecentPaths.updated(["~/a"], adding: "") == ["~/a"])
        #expect(RecentPaths.updated(["~/a"], adding: "   ") == ["~/a"])
    }

    @Test func listIsCappedAtLimitDroppingOldest() {
        let existing = ["1", "2", "3"]
        let updated = RecentPaths.updated(existing, adding: "0", limit: 3)
        #expect(updated == ["0", "1", "2"])
    }

    @Test func defaultLimitIsEight() {
        let existing = (1...8).map(String.init)
        let updated = RecentPaths.updated(existing, adding: "0")
        #expect(updated.count == 8)
        #expect(updated.first == "0")
        #expect(!updated.contains("8"))
    }
}
