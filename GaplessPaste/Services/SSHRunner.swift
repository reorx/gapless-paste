import Foundation
import GaplessPasteCore

// Process 执行 ssh/scp + 超时 + stdout/stderr 采集。
// 上层（AppState）以 isBusy 保证单任务串行，这里不做队列。
// 每条命令的 argv、耗时、退出码、stderr 全部进日志，便于命令行侧排错。

struct CommandResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool { exitCode == 0 }

    /// 失败通知里只展示 stderr 首行
    var firstStderrLine: String {
        stderr.split(separator: "\n").first.map(String.init) ?? "exit \(exitCode)"
    }
}

enum SSHRunnerError: Error, LocalizedError {
    case timeout(seconds: TimeInterval)

    var errorDescription: String? {
        switch self {
        case .timeout(let seconds):
            return "命令超时（\(Int(seconds))s）"
        }
    }
}

final class SSHRunner: Sendable {
    private let log: LogService

    init(log: LogService) {
        self.log = log
    }

    func run(_ argv: [String], timeout: TimeInterval = 60) async throws -> CommandResult {
        log.debug("$ \(LogFormatter.describeCommand(argv))")
        let started = Date()
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [log] in
                do {
                    let result = try Self.runBlocking(argv, timeout: timeout)
                    let elapsed = String(format: "%.2fs", Date().timeIntervalSince(started))
                    if result.succeeded {
                        log.debug("exit 0 (\(elapsed))")
                    } else {
                        var message = "exit \(result.exitCode) (\(elapsed))"
                        if !result.stderr.isEmpty {
                            message += "\nstderr: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
                        }
                        log.info(message)
                    }
                    continuation.resume(returning: result)
                } catch {
                    log.error("命令异常：\(error.localizedDescription)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func runBlocking(_ argv: [String], timeout: TimeInterval) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: argv[0])
        process.arguments = Array(argv.dropFirst())
        process.standardInput = FileHandle.nullDevice
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // 超时看门狗：到点 SIGTERM，读端随 EOF 返回
        let timedOut = NSMutableString(string: "")
        let watchdog = DispatchWorkItem {
            if process.isRunning {
                timedOut.setString("1")
                process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

        // 两个管道并发读到 EOF，避免单边缓冲区塞满导致死锁
        var stdoutData = Data()
        var stderrData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.wait()
        process.waitUntilExit()
        watchdog.cancel()

        if timedOut.isEqual(to: "1") {
            throw SSHRunnerError.timeout(seconds: timeout)
        }
        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }
}
