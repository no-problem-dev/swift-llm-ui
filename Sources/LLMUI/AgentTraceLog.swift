import AgentLoopKit
import Foundation
import LLMClient
import Observation

// MARK: - AgentTraceLog

/// What happened during a run, kept so a screen can show it.
///
/// `AgentLoop` reports what it is doing through its event stream and what it cost through
/// ``AgentTelemetry``; neither is retained, so by the time a person wants to look, it is gone.
/// This holds both in one ordered list, oldest first, capped so a long session cannot grow
/// without bound.
///
/// It lives here rather than beside the loop because it is view state — `@MainActor` and
/// `@Observable` — and the loop is deliberately free of both so it can run on a server.
@MainActor
@Observable
public final class AgentTraceLog {
    public private(set) var entries: [Entry] = []

    private let limit: Int

    /// - Parameter limit: How many entries to keep. Oldest are dropped first.
    public init(limit: Int = 500) {
        self.limit = limit
    }

    // MARK: - Entry

    public struct Entry: Identifiable, Sendable, Hashable {
        public let id: UUID
        public let at: Date
        public let kind: Kind

        /// One line, shown in the list.
        public let summary: String

        /// The long form — a full prompt, a tool's arguments — shown when the entry is opened.
        public let detail: String?

        public init(
            id: UUID = UUID(),
            at: Date = Date(),
            kind: Kind,
            summary: String,
            detail: String? = nil
        ) {
            self.id = id
            self.at = at
            self.kind = kind
            self.summary = summary
            self.detail = detail
        }
    }

    /// What an entry is about. Used to filter the list and to pick an icon.
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        case run
        case text
        case tool
        case surface
        case failure
        case llm

        /// An SF Symbol name.
        public var systemImage: String {
            switch self {
            case .run: "play.circle"
            case .text: "text.alignleft"
            case .tool: "wrench"
            case .surface: "square.stack.3d.up"
            case .failure: "exclamationmark.triangle"
            case .llm: "brain"
            }
        }
    }

    // MARK: - Recording

    public func append(_ kind: Kind, _ summary: String, detail: String? = nil) {
        entries.append(Entry(kind: kind, summary: summary, detail: detail))
        if entries.count > limit {
            entries.removeFirst(entries.count - limit)
        }
    }

    /// Appends to the previous entry when it is the same kind, instead of adding a new one.
    ///
    /// Streamed text arrives one delta at a time. Appending each as its own entry turns a
    /// sentence into dozens of rows, so the deltas are joined back into the entry they belong to.
    public func appendMergingSummary(_ kind: Kind, _ delta: String) {
        guard let last = entries.last, last.kind == kind else {
            append(kind, delta)
            return
        }
        entries[entries.count - 1] = Entry(
            id: last.id,
            at: last.at,
            kind: kind,
            summary: last.summary + delta,
            detail: last.detail
        )
    }

    /// Like ``appendMergingSummary(_:_:)``, but the deltas join the detail and the summary stays
    /// put — for a tool's arguments, which stream in under a fixed heading.
    public func appendMergingDetail(_ kind: Kind, summary: String, delta: String) {
        guard let last = entries.last, last.kind == kind, last.summary == summary else {
            append(kind, summary, detail: delta)
            return
        }
        entries[entries.count - 1] = Entry(
            id: last.id,
            at: last.at,
            kind: kind,
            summary: summary,
            detail: (last.detail ?? "") + delta
        )
    }

    /// Records one telemetry report from a run.
    ///
    /// Pass this as the loop's sink to get the assembled system prompt and each step's token
    /// count without writing the formatting yourself.
    public func record(_ telemetry: AgentTelemetry) {
        switch telemetry {
        case .systemPrompt(let rendered):
            append(.llm, "systemPrompt — \(rendered.count) characters", detail: rendered)

        case .usage(let usage, let model):
            append(.llm, "usage — \(model)", detail: Self.describe(usage))

        case .validationFailed(let issues, let willRetry):
            append(
                .failure,
                willRetry ? "validation failed, retrying" : "validation failed",
                detail: issues.joined(separator: "\n")
            )
        }
    }

    public func clear() {
        entries.removeAll()
    }

    // MARK: - Reading

    /// The whole log as text, for putting on the pasteboard.
    public func transcript() -> String {
        entries.map { entry in
            let head = "[\(Self.timeFormatter.string(from: entry.at))] \(entry.kind.rawValue)\n\(entry.summary)"
            guard let detail = entry.detail, !detail.isEmpty else {
                return head
            }
            return head + "\n" + detail
        }
        .joined(separator: "\n\n")
    }

    /// Spells out a step's token counts, leaving out the ones the provider did not report.
    public static func describe(_ usage: TokenUsage) -> String {
        var parts = ["in \(usage.inputTokens)", "out \(usage.outputTokens)"]
        if let reasoning = usage.reasoningTokens {
            parts.append("reasoning \(reasoning)")
        }
        if let cacheRead = usage.cacheReadTokens {
            parts.append("cache read \(cacheRead)")
        }
        if let cacheWrite = usage.cacheCreationTokens {
            parts.append("cache write \(cacheWrite)")
        }
        parts.append("total \(usage.totalTokens)")
        return parts.joined(separator: " / ")
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}
