import Foundation

/// 仅保存可展示的元数据，不持有剪贴板正文或图像数据。
public struct TransferContent: Equatable, Sendable {
    public enum Kind: Sendable { case clipboard, image, text, files }
    public var kind: Kind
    public var fileNames: [String]
    public var byteCount: Int?
    public var characterCount: Int?

    public init(kind: Kind, fileNames: [String] = [], byteCount: Int? = nil, characterCount: Int? = nil) {
        self.kind = kind
        self.fileNames = fileNames
        self.byteCount = byteCount
        self.characterCount = characterCount
    }

    public var label: String {
        switch kind {
        case .clipboard: return "剪贴板"
        case .image: return "图像"
        case .text: return "文本"
        case .files: return fileNames.count > 1 ? "\(fileNames.count) 个文件" : "文件"
        }
    }
}

public struct TransferRecord: Identifiable, Equatable, Sendable {
    public enum Operation: Sendable { case upload, pushClipboard, pullClipboard }
    public enum Outcome: Sendable { case running, success, failure, partialSuccess }
    public let id: UUID
    public let operation: Operation
    public let machine: String
    public let directory: String?
    public var content: TransferContent
    public let startedAt: Date
    public var finishedAt: Date?
    public var outcome: Outcome = .running
    public var message: String?
    public var remotePaths: [String] = []

    public init(id: UUID = UUID(), operation: Operation, machine: String, directory: String? = nil, content: TransferContent, startedAt: Date = Date()) {
        self.id = id
        self.operation = operation
        self.machine = machine
        self.directory = directory
        self.content = content
        self.startedAt = startedAt
    }

    public var direction: String {
        operation == .pullClipboard ? "\(machine) → 本机" : "本机 → \(machine)"
    }

    public var title: String {
        switch outcome {
        case .partialSuccess: return "已上传，剪贴板写入失败"
        case .failure:
            switch operation {
            case .upload: return "上传失败"
            case .pushClipboard: return "同步失败"
            case .pullClipboard: return "接收失败"
            }
        case .running:
            switch operation {
            case .upload: return "正在上传到远端…"
            case .pushClipboard: return "正在同步到远端…"
            case .pullClipboard: return "正在接收剪贴板…"
            }
        case .success:
            switch operation {
            case .upload: return "已上传到远端"
            case .pushClipboard: return "已同步到远端"
            case .pullClipboard: return "已接收到本机"
            }
        }
    }

    public var needsAttention: Bool { outcome == .failure || outcome == .partialSuccess }
}

/// 最近记录与图标反馈分离；所有异步事件按操作 ID 校验，时钟由调用者注入。
public struct TransferPresentation: Equatable, Sendable {
    public enum Feedback: String, CaseIterable, Sendable {
        case idle, sending, receiving, success, attention
        public var symbolName: String? {
            switch self {
            case .idle: return nil
            case .sending: return "arrow.up"
            case .receiving: return "arrow.down"
            case .success: return "checkmark"
            case .attention: return "exclamationmark"
            }
        }
    }

    public private(set) var record: TransferRecord?
    public private(set) var feedback: Feedback = .idle
    private var previousRecord: TransferRecord?
    public init() {}
    public var isBusy: Bool { record?.outcome == .running }
    public var title: String { record?.title ?? "还没有传输记录" }

    public func subtitle(at now: Date = Date()) -> String {
        guard let record else { return "拷贝内容后，选择下方的上传或同步" }
        var parts = [record.content.label, record.direction]
        if let finished = record.finishedAt { parts.append(DisplayFormatter.relativeTimeText(from: finished, to: now)) }
        return parts.joined(separator: " · ")
    }

    public mutating func begin(_ record: TransferRecord) {
        guard !isBusy else { return }
        previousRecord = self.record
        self.record = record
        feedback = record.operation == .pullClipboard ? .receiving : .sending
    }

    public mutating func updateContent(id: UUID, content: TransferContent) {
        guard record?.id == id, isBusy else { return }
        record?.content = content
    }

    public mutating func finish(id: UUID, outcome: TransferRecord.Outcome, at now: Date, message: String? = nil, remotePaths: [String] = []) {
        guard record?.id == id, isBusy, outcome != .running else { return }
        record?.outcome = outcome
        record?.finishedAt = now
        record?.message = message
        record?.remotePaths = remotePaths
        previousRecord = nil
        feedback = outcome == .success ? .success : .attention
    }

    public mutating func abandon(id: UUID) {
        guard record?.id == id, isBusy else { return }
        record = previousRecord
        previousRecord = nil
        feedback = .idle
    }

    public mutating func acknowledge(id: UUID) {
        guard record?.id == id, feedback == .attention else { return }
        feedback = .idle
    }

    public mutating func expireSuccess(id: UUID, at now: Date) {
        guard record?.id == id, feedback == .success, let finished = record?.finishedAt,
              now.timeIntervalSince(finished) >= 2 else { return }
        feedback = .idle
    }

    public func shouldAnimate(at now: Date, reduceMotion: Bool) -> Bool {
        guard !reduceMotion, isBusy, let record else { return false }
        return now >= record.startedAt.addingTimeInterval(0.3)
    }
}
