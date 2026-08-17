import AgentLoopKit
import Foundation
import LLMClient
import Observation

// MARK: - AgentTraceLog

/// What happened during a run, kept so a screen can show it.
///
/// `AgentLoop` reports what it is doing through its event stream and what it cost through
/// `AgentTelemetry`; neither is retained, so by the time a person wants to look, it is gone.
/// This holds both in one ordered list, oldest first, capped so a long session cannot grow
/// without bound.
///
/// Entries are stamped with the run they belong to, and ``runs`` groups them back. A run is the
/// unit a person actually reasons about — "the one I just sent" — so it is stored rather than
/// inferred from where a `run.started` line happens to sit.
///
/// It lives here rather than beside the loop because it is view state — `@MainActor` and
/// `@Observable` — and the loop is deliberately free of both so it can run on a server.
@MainActor
@Observable
public final class AgentTraceLog {
    public private(set) var entries: [Entry] = []

    /// The run currently open, or `nil` before the first ``beginRun(label:)``.
    public private(set) var currentRunID: UUID?

    private var runLabels: [UUID: String] = [:]
    private var runOrder: [UUID] = []
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

        /// The run this belongs to, or `nil` when it happened outside one.
        public let runID: UUID?

        /// One line, shown in the list.
        public let summary: String

        /// The long form — a full prompt, a tool's arguments — shown when the entry is opened.
        public let detail: String?

        /// A second long form shown beside ``detail``, for an entry that has two sides.
        ///
        /// A tool call is one thing that happened, not two: the arguments and the result are the
        /// question and its answer. Keeping them on one entry is what lets a screen show them
        /// together instead of making someone match up two rows by eye.
        public let result: String?

        public init(
            id: UUID = UUID(),
            at: Date = Date(),
            kind: Kind,
            runID: UUID? = nil,
            summary: String,
            detail: String? = nil,
            result: String? = nil
        ) {
            self.id = id
            self.at = at
            self.kind = kind
            self.runID = runID
            self.summary = summary
            self.detail = detail
            self.result = result
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

        /// How the kind is named in a filter or a header.
        public var label: String {
            switch self {
            case .run: "Run"
            case .text: "Text"
            case .tool: "Tool"
            case .surface: "Surface"
            case .failure: "Error"
            case .llm: "LLM"
            }
        }

        /// The colour this kind is drawn in, so a list can be skimmed by hue.
        ///
        /// Semantic rather than decorative: failures are the only red, and everything that costs
        /// money shares one colour.
        public var tintName: TintName {
            switch self {
            case .run: .neutral
            case .text: .neutral
            case .tool: .warm
            case .surface: .cool
            case .failure: .alarming
            case .llm: .spending
            }
        }

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

    /// Names a colour without naming a UI framework, so the log stays drawable anywhere.
    public enum TintName: String, Sendable, Hashable {
        case neutral
        case warm
        case cool
        case alarming
        case spending
    }

    // MARK: - Run

    /// One execution, and everything recorded during it.
    ///
    /// Assembled from ``entries`` rather than stored, so there is one copy of the truth and a run
    /// cannot disagree with the entries it contains.
    public struct Run: Identifiable, Sendable, Hashable {
        public let id: UUID

        /// 1-based, in the order runs were begun.
        public let index: Int

        /// What started the run — usually the message. Shown to tell runs apart.
        public let label: String?

        public let entries: [Entry]

        public var at: Date? {
            entries.first?.at
        }

        /// How long it ran, or `nil` when fewer than two entries were recorded.
        public var duration: TimeInterval? {
            guard let first = entries.first?.at, let last = entries.last?.at, entries.count > 1
            else {
                return nil
            }
            return last.timeIntervalSince(first)
        }

        /// True when anything in the run failed.
        ///
        /// A run that recovered on retry still counts: the failure happened, and hiding it is how
        /// a flaky prompt goes unnoticed.
        public var hasFailure: Bool {
            entries.contains { $0.kind == .failure }
        }

        public func count(of kind: Kind) -> Int {
            entries.count { $0.kind == kind }
        }
    }

    /// Every run, newest last, each with the entries recorded during it.
    ///
    /// Entries recorded before any run was begun are gathered into one unlabelled run at the
    /// front, so nothing is dropped for arriving early.
    public var runs: [Run] {
        var grouped: [UUID?: [Entry]] = [:]
        for entry in entries {
            grouped[entry.runID, default: []].append(entry)
        }

        var result: [Run] = []
        if let loose = grouped[UUID?.none], !loose.isEmpty {
            result.append(Run(id: UUID(), index: 0, label: nil, entries: loose))
        }
        for (offset, runID) in runOrder.enumerated() {
            guard let entries = grouped[runID], !entries.isEmpty else {
                continue
            }
            result.append(
                Run(id: runID, index: offset + 1, label: runLabels[runID], entries: entries)
            )
        }
        return result
    }

    // MARK: - Recording

    /// Opens a run. Entries recorded afterwards belong to it.
    ///
    /// - Parameter label: What started it, shown to tell runs apart.
    /// - Returns: The run's identifier, for pairing it with a ledger turn.
    @discardableResult
    public func beginRun(label: String? = nil) -> UUID {
        let id = UUID()
        currentRunID = id
        runOrder.append(id)
        if let label {
            runLabels[id] = label
        }
        return id
    }

    /// Closes the current run, so later entries are not attributed to it.
    public func endRun() {
        currentRunID = nil
    }

    public func append(
        _ kind: Kind,
        _ summary: String,
        detail: String? = nil,
        result: String? = nil
    ) {
        entries.append(
            Entry(kind: kind, runID: currentRunID, summary: summary, detail: detail, result: result)
        )
        prune()
    }

    /// Appends to the previous entry when it is the same kind, instead of adding a new one.
    ///
    /// Streamed text arrives one delta at a time. Appending each as its own entry turns a
    /// sentence into dozens of rows, so the deltas are joined back into the entry they belong to.
    public func appendMergingSummary(_ kind: Kind, _ delta: String) {
        guard let last = entries.last, last.kind == kind, last.runID == currentRunID else {
            append(kind, delta)
            return
        }
        entries[entries.count - 1] = Entry(
            id: last.id,
            at: last.at,
            kind: kind,
            runID: last.runID,
            summary: last.summary + delta,
            detail: last.detail,
            result: last.result
        )
    }

    /// Like ``appendMergingSummary(_:_:)``, but the deltas join the detail and the summary stays
    /// put — for a tool's arguments, which stream in under a fixed heading.
    public func appendMergingDetail(_ kind: Kind, summary: String, delta: String) {
        guard
            let last = entries.last,
            last.kind == kind,
            last.summary == summary,
            last.runID == currentRunID
        else {
            append(kind, summary, detail: delta)
            return
        }
        entries[entries.count - 1] = Entry(
            id: last.id,
            at: last.at,
            kind: kind,
            runID: last.runID,
            summary: summary,
            detail: (last.detail ?? "") + delta,
            result: last.result
        )
    }

    /// Attaches a result to the most recent entry matching `kind` and `summary` in the open run.
    ///
    /// A tool's result arrives well after its arguments, with other entries in between. Rather
    /// than landing as a separate row that has to be matched up by eye, it joins the call it
    /// answers. Answers nothing when no such call is open, so a stray result cannot attach itself
    /// to an unrelated entry.
    @discardableResult
    public func attachResult(_ result: String, to kind: Kind, summary: String) -> Bool {
        guard
            let index = entries.lastIndex(where: {
                $0.kind == kind && $0.summary == summary && $0.runID == currentRunID
                    && $0.result == nil
            })
        else {
            return false
        }
        let existing = entries[index]
        entries[index] = Entry(
            id: existing.id,
            at: existing.at,
            kind: kind,
            runID: existing.runID,
            summary: existing.summary,
            detail: existing.detail,
            result: result
        )
        return true
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
        runLabels.removeAll()
        runOrder.removeAll()
        currentRunID = nil
    }

    /// Drops the oldest entries past the limit, and forgets runs left with nothing in them.
    private func prune() {
        guard entries.count > limit else {
            return
        }
        entries.removeFirst(entries.count - limit)

        let surviving = Set(entries.compactMap(\.runID))
        runOrder.removeAll { $0 != currentRunID && !surviving.contains($0) }
        runLabels = runLabels.filter { surviving.contains($0.key) || $0.key == currentRunID }
    }

    // MARK: - Reading

    /// The whole log as text, for putting on the pasteboard.
    public func transcript() -> String {
        entries.map(Self.describe).joined(separator: "\n\n")
    }

    /// One run as text, for putting on the pasteboard.
    ///
    /// A run is the unit worth pasting into a bug report; the whole session is usually too much.
    public func transcript(of run: Run) -> String {
        let head = "=== \(run.label ?? "Run \(run.index)") ==="
        return ([head] + run.entries.map(Self.describe)).joined(separator: "\n\n")
    }

    private static func describe(_ entry: Entry) -> String {
        var text = "[\(timeFormatter.string(from: entry.at))] \(entry.kind.rawValue)\n\(entry.summary)"
        if let detail = entry.detail, !detail.isEmpty {
            text += "\n" + detail
        }
        if let result = entry.result, !result.isEmpty {
            text += "\n→ " + result
        }
        return text
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
