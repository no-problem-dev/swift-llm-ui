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

    // MARK: - Runs

    @Test("Entries are grouped into the run they were recorded in")
    func entriesGroupIntoRuns() {
        let log = AgentTraceLog()

        log.beginRun(label: "first")
        log.append(.text, "a")
        log.beginRun(label: "second")
        log.append(.text, "b")
        log.append(.text, "c")

        let runs = log.runs
        #expect(runs.count == 2)
        #expect(runs[0].label == "first")
        #expect(runs[0].entries.count == 1)
        #expect(runs[1].label == "second")
        #expect(runs[1].entries.count == 2)
    }

    /// Runs are numbered in the order they were begun, so the label matches what a person saw.
    @Test("Runs are numbered from one")
    func runsAreNumberedInOrder() {
        let log = AgentTraceLog()

        log.beginRun()
        log.append(.text, "a")
        log.beginRun()
        log.append(.text, "b")

        #expect(log.runs.map(\.index) == [1, 2])
    }

    /// Dropping an entry recorded before any run would silently lose the earliest evidence.
    @Test("Entries recorded before any run are kept")
    func looseEntriesAreKept() {
        let log = AgentTraceLog()

        log.append(.failure, "before anything")
        log.beginRun(label: "first")
        log.append(.text, "a")

        let runs = log.runs
        #expect(runs.count == 2)
        #expect(runs[0].label == nil)
        #expect(runs[0].entries[0].summary == "before anything")
        #expect(runs[1].label == "first")
    }

    @Test("Ending a run detaches later entries from it")
    func endingARunDetachesLaterEntries() {
        let log = AgentTraceLog()

        log.beginRun(label: "first")
        log.append(.text, "inside")
        log.endRun()
        log.append(.failure, "outside")

        let runs = log.runs
        #expect(runs.count == 2)
        #expect(runs[0].label == nil)
        #expect(runs[0].entries.map(\.summary) == ["outside"])
        #expect(runs[1].entries.map(\.summary) == ["inside"])
    }

    /// A run that recovered still failed, and hiding that is how a flaky prompt goes unnoticed.
    @Test("A run reports a failure even when later entries succeed")
    func failureIsReportedEvenAfterRecovery() {
        let log = AgentTraceLog()

        log.beginRun()
        log.append(.failure, "validation failed, retrying")
        log.append(.surface, "ok")

        #expect(log.runs[0].hasFailure)
    }

    @Test("A run counts the entries of one kind")
    func runCountsByKind() {
        let log = AgentTraceLog()

        log.beginRun()
        log.append(.tool, "a")
        log.append(.tool, "b")
        log.append(.text, "c")

        #expect(log.runs[0].count(of: .tool) == 2)
        #expect(log.runs[0].count(of: .text) == 1)
        #expect(log.runs[0].count(of: .llm) == 0)
    }

    /// Merging must not reach across a run boundary, or the last line of one run absorbs the
    /// first of the next.
    @Test("Text deltas do not merge across a run boundary")
    func deltasDoNotMergeAcrossRuns() {
        let log = AgentTraceLog()

        log.beginRun()
        log.appendMergingSummary(.text, "first")
        log.beginRun()
        log.appendMergingSummary(.text, "second")

        #expect(log.entries.count == 2)
        #expect(log.runs[0].entries[0].summary == "first")
        #expect(log.runs[1].entries[0].summary == "second")
    }

    /// A run left with no surviving entries would otherwise sit in the list showing nothing.
    @Test("Runs emptied by the limit disappear")
    func emptiedRunsDisappear() {
        let log = AgentTraceLog(limit: 2)

        log.beginRun(label: "old")
        log.append(.text, "a")
        log.beginRun(label: "new")
        log.append(.text, "b")
        log.append(.text, "c")

        let runs = log.runs
        #expect(runs.count == 1)
        #expect(runs[0].label == "new")
    }

    // MARK: - Results

    /// A tool call is one thing, not two rows to match up by eye.
    @Test("A result joins the call it answers")
    func resultJoinsItsCall() {
        let log = AgentTraceLog()

        log.beginRun()
        log.append(.tool, "search", detail: "{\"q\":\"rice\"}")
        log.append(.llm, "usage — gpt")
        let attached = log.attachResult("3 recipes", to: .tool, summary: "search")

        #expect(attached)
        #expect(log.entries.count == 2)
        #expect(log.entries[0].result == "3 recipes")
    }

    /// A stray result must not attach itself to an unrelated entry.
    @Test("A result with no matching call is refused")
    func resultWithoutACallIsRefused() {
        let log = AgentTraceLog()

        log.beginRun()
        log.append(.text, "hello")

        #expect(!log.attachResult("orphan", to: .tool, summary: "search"))
    }

    /// Two calls to the same tool each get their own result, newest first.
    @Test("A result attaches to the most recent unanswered call")
    func resultAttachesToTheLatestUnansweredCall() {
        let log = AgentTraceLog()

        log.beginRun()
        log.append(.tool, "search")
        log.append(.tool, "search")
        log.attachResult("second", to: .tool, summary: "search")
        log.attachResult("first", to: .tool, summary: "search")

        #expect(log.entries[0].result == "first")
        #expect(log.entries[1].result == "second")
    }

    @Test("A run's transcript carries only that run")
    func runTranscriptIsScoped() {
        let log = AgentTraceLog()

        log.beginRun(label: "first")
        log.append(.text, "inside")
        log.beginRun(label: "second")
        log.append(.text, "elsewhere")

        let transcript = log.transcript(of: log.runs[0])

        #expect(transcript.contains("inside"))
        #expect(!transcript.contains("elsewhere"))
        #expect(transcript.contains("first"))
    }

    @Test("A transcript carries the result too")
    func transcriptCarriesResults() {
        let log = AgentTraceLog()
        log.append(.tool, "search", detail: "{\"q\":\"rice\"}", result: "3 recipes")

        #expect(log.transcript().contains("3 recipes"))
    }

    @Test("Clearing forgets the runs as well")
    func clearForgetsRuns() {
        let log = AgentTraceLog()
        log.beginRun(label: "first")
        log.append(.text, "a")

        log.clear()

        #expect(log.runs.isEmpty)
        #expect(log.currentRunID == nil)
    }
}
