import Testing
import Foundation
@testable import GaplessPasteCore

// 持久化预览缓存的路径映射：机器-远端路径 → 稳定的缓存相对路径。
// 要求：同输入恒同输出（跨进程重启仍命中）、不同机器/路径互不冲突、
// 末段保留原始文件名（复制/下载导出时拿到原名）、各段文件系统安全。

@Suite("PreviewCache")
struct PreviewCacheTests {
    @Test("同机器同路径映射稳定（持久化缓存跨会话命中的前提）")
    func stableMapping() {
        let a = PreviewCache.relativePath(sshAlias: "dev", remotePath: "/home/reorx/shot.png")
        let b = PreviewCache.relativePath(sshAlias: "dev", remotePath: "/home/reorx/shot.png")
        #expect(a == b)
    }

    @Test("不同远端路径映射到不同缓存位置")
    func distinctPaths() {
        let a = PreviewCache.relativePath(sshAlias: "dev", remotePath: "/home/reorx/a/shot.png")
        let b = PreviewCache.relativePath(sshAlias: "dev", remotePath: "/home/reorx/b/shot.png")
        #expect(a != b)
    }

    @Test("不同机器的同名路径互不冲突")
    func distinctMachines() {
        let a = PreviewCache.relativePath(sshAlias: "dev", remotePath: "/tmp/x.txt")
        let b = PreviewCache.relativePath(sshAlias: "prod", remotePath: "/tmp/x.txt")
        #expect(a != b)
    }

    @Test("末段保留原始文件名")
    func preservesFileName() {
        let path = PreviewCache.relativePath(sshAlias: "dev", remotePath: "/var/log/系统 日志.log")
        #expect(path.hasSuffix("/系统 日志.log"))
    }

    @Test("相对路径固定三段：alias / 路径散列 / 文件名")
    func threeSegments() {
        let path = PreviewCache.relativePath(sshAlias: "dev", remotePath: "/home/reorx/shot.png")
        let segments = path.split(separator: "/", omittingEmptySubsequences: false)
        #expect(segments.count == 3)
        #expect(segments[0] == "dev")
        #expect(segments[2] == "shot.png")
    }

    @Test("alias 中的路径分隔符等不安全字符被替换，不产生额外层级")
    func sanitizesAlias() {
        let path = PreviewCache.relativePath(sshAlias: "user@host:22/x", remotePath: "/tmp/a.txt")
        let segments = path.split(separator: "/", omittingEmptySubsequences: false)
        #expect(segments.count == 3)
        #expect(!segments[0].contains(":"))
    }

    @Test("生成的是安全相对路径：不以 / 开头、无 .. 段")
    func safeRelativePath() {
        let path = PreviewCache.relativePath(sshAlias: "dev", remotePath: "/home/../etc/passwd")
        #expect(!path.hasPrefix("/"))
        #expect(!path.split(separator: "/").contains(".."))
    }

    @Test("散列取完整远端路径：同目录不同文件的散列段也不同")
    func hashIsPerFullPath() {
        // 保证 a/x.txt 与 b/x.txt、/data/x.txt 与 /data/y.txt 绝不互相覆盖
        let a = PreviewCache.relativePath(sshAlias: "dev", remotePath: "/data/x.txt")
        let b = PreviewCache.relativePath(sshAlias: "dev", remotePath: "/data/y.txt")
        let hashA = a.split(separator: "/")[1]
        let hashB = b.split(separator: "/")[1]
        #expect(hashA != hashB)
    }
}
