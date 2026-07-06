import Foundation
import GaplessPasteCore

// 首次对某机器操作时探测 $HOME + uname，结果缓存进 UserDefaults；
// 「重载配置」时清缓存（spec：路径回传的绝对化）

@MainActor
final class ProbeService {
    private let runner: SSHRunner
    private let builder: SSHCommandBuilder
    private var cache: [String: ProbeResult]
    private static let defaultsKey = "probeCache"

    init(runner: SSHRunner, builder: SSHCommandBuilder) {
        self.runner = runner
        self.builder = builder
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([String: ProbeResult].self, from: data) {
            cache = decoded
        } else {
            cache = [:]
        }
    }

    func probe(_ sshAlias: String) async throws -> ProbeResult {
        if let cached = cache[sshAlias] {
            return cached
        }
        let result = try await runner.run(builder.probeCommand(host: sshAlias), timeout: 20)
        guard result.succeeded, let probe = ProbeResult.parse(result.stdout) else {
            throw AppError.probeFailed(alias: sshAlias, detail: result.firstStderrLine)
        }
        cache[sshAlias] = probe
        persist()
        return probe
    }

    func clearCache() {
        cache = [:]
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
