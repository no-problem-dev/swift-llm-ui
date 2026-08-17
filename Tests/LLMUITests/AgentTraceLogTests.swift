import AgentLoopKit
import Foundation
import LLMClient
import Testing

@testable import LLMUI

/// Collecting a run into something readable.
@MainActor
@Suite("Agent trace log")
struct AgentTraceLogTests {

    /// Streamed text arrives one delta at a time. Left alone, a sentence becomes dozens of rows.
    @Test("Consecutive text deltas join one entry")
    func textDeltasMergeIntoOneEntry() {
        let log = AgentTraceLog()

        log.appendMergingSummary(.text, "Hello")
        log.appendMergingSummary(.text, ", ")
        log.appendMergingSummary(.text, "world")

        #expect(log.entries.count == 1)
        #expect(log.entries[0].summary == "Hello, world")
    }

    /// Merging must stop at a different kind, or a tool call swallows the text around it.
    @Test("A different kind breaks the merge")
    func aDifferentKindStartsANewEntry() {
        let log = AgentTraceLog()

        log.appendMergingSummary(.text, "before")
        log.append(.tool, "search")
        log.appendMergingSummary(.text, "after")

        #expect(log.entries.map(\.summary) == ["before", "search", "after"])
    }

    /// Tool arguments stream in under a fixed heading, so the deltas belong in the detail.
    @Test("Argument deltas join the detail, not the summary")
    func argumentDeltasMergeIntoDetail() {
        let log = AgentTraceLog()

        log.appendMergingDetail(.tool, summary: "arguments", delta: "{\"q\":")
        log.appendMergingDetail(.tool, summary: "arguments", delta: "\"rice\"}")

        #expect(log.entries.count == 1)
        #expect(log.entries[0].summary == "arguments")
        #expect(log.entries[0].detail == "{\"q\":\"rice\"}")
    }

    @Test("A different heading starts a new entry")
    func aDifferentHeadingStartsANewEntry() {
        let log = AgentTraceLog()

        log.appendMergingDetail(.tool, summary: "arguments", delta: "a")
        log.appendMergingDetail(.tool, summary: "result", delta: "b")

        #expect(log.entries.count == 2)
    }

    /// A long session must not grow without bound; the oldest go first.
    @Test("The oldest entries are dropped at the limit")
    func oldestEntriesAreDropped() {
        let log = AgentTraceLog(limit: 3)

        for index in 1...5 {
            log.append(.run, "\(index)")
        }

        #expect(log.entries.map(\.summary) == ["3", "4", "5"])
    }

    @Test("Telemetry is recorded under the llm kind")
    func telemetryIsRecorded() {
        let log = AgentTraceLog()

        log.record(.systemPrompt(rendered: "You are helpful."))

        #expect(log.entries.count == 1)
        #expect(log.entries[0].kind == .llm)
        #expect(log.entries[0].detail == "You are helpful.")
    }

    /// A validation failure that will be retried reads differently from a final one, so an
    /// observer can tell "about to be replaced" from "this is the answer".
    @Test("A retried validation failure says so")
    func validationFailureDistinguishesRetry() {
        let log = AgentTraceLog()

        log.record(.validationFailed(issues: ["bad"], willRetry: true))
        log.record(.validationFailed(issues: ["bad"], willRetry: false))

        #expect(log.entries[0].kind == .failure)
        #expect(log.entries[0].summary.contains("retrying"))
        #expect(!log.entries[1].summary.contains("retrying"))
    }

    /// Counts the provider did not report are left out rather than shown as zero.
    @Test("Unreported token counts are left out")
    func unreportedCountsAreOmitted() {
        let usage = TokenUsage(inputTokens: 10, outputTokens: 20)

        let text = AgentTraceLog.describe(usage)

        #expect(text.contains("in 10"))
        #expect(text.contains("out 20"))
        #expect(text.contains("total 30"))
        #expect(!text.contains("reasoning"))
        #expect(!text.contains("cache"))
    }

    @Test("Clearing empties the log")
    func clearEmptiesTheLog() {
        let log = AgentTraceLog()
        log.append(.run, "started")

        log.clear()

        #expect(log.entries.isEmpty)
    }

    @Test("The transcript carries summaries and details")
    func transcriptCarriesBoth() {
        let log = AgentTraceLog()
        log.append(.tool, "search", detail: "{\"q\":\"rice\"}")

        let transcript = log.transcript()

        #expect(transcript.contains("search"))
        #expect(transcript.contains("{\"q\":\"rice\"}"))
        #expect(transcript.contains("tool"))
    }
}
