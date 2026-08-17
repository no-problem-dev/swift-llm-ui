import Foundation
import LLMClient
import Observation

// MARK: - UsageStep

/// One model call: what it spent and what it cost.
///
/// A turn is usually several of these — the model answers, calls a tool, reads the result, answers
/// again — and they can be served by different models when a sub-agent is cheaper than the main
/// one. Keeping the step as the unit is what makes that visible; totals alone hide it.
public struct UsageStep: Sendable, Identifiable, Hashable {
    public let id: UUID

    /// 1-based within its turn.
    public let index: Int

    /// The model that served this step, as `ModelDescriptor.modelID`.
    public let modelID: String

    public let usage: TokenUsage

    /// What the step cost, or `nil` when no price sheet was known for the model.
    ///
    /// Nil is not zero: a step whose price is unknown is left out of the totals rather than
    /// counted as free, and the UI says so instead of quietly under-reporting.
    public let cost: Money<USD>?

    public let at: Date

    public init(
        id: UUID = UUID(),
        index: Int,
        modelID: String,
        usage: TokenUsage,
        cost: Money<USD>?,
        at: Date = Date()
    ) {
        self.id = id
        self.index = index
        self.modelID = modelID
        self.usage = usage
        self.cost = cost
        self.at = at
    }
}

// MARK: - UsageTurn

/// One thing the user asked for, and every model call it took to answer.
public struct UsageTurn: Sendable, Identifiable, Hashable {
    public let id: UUID

    /// 1-based.
    public let index: Int

    /// What the turn was about — usually the message that started it. Shown to tell turns apart.
    public let label: String?

    public var steps: [UsageStep]

    public let at: Date

    public init(
        id: UUID = UUID(),
        index: Int,
        label: String? = nil,
        steps: [UsageStep] = [],
        at: Date = Date()
    ) {
        self.id = id
        self.index = index
        self.label = label
        self.steps = steps
        self.at = at
    }

    public var usage: TokenUsage {
        steps.map(\.usage).reduce(.zero, +)
    }

    /// The sum of the steps whose cost is known.
    public var cost: Money<USD> {
        steps.compactMap(\.cost).reduce(.zero, +)
    }

    /// True when any step could not be priced, so ``cost`` is a floor rather than the total.
    public var hasUnpricedSteps: Bool {
        steps.contains { $0.cost == nil }
    }

    /// Every model that served part of this turn, in the order they first appear.
    public var modelIDs: [String] {
        var seen: Set<String> = []
        return steps.compactMap { seen.insert($0.modelID).inserted ? $0.modelID : nil }
    }
}

// MARK: - UsageTotals

/// What a set of turns came to.
public struct UsageTotals: Sendable, Hashable {
    public let turnCount: Int
    public let stepCount: Int
    public let usage: TokenUsage
    public let cost: Money<USD>
    public let hasUnpricedSteps: Bool

    public static let zero = UsageTotals(
        turnCount: 0, stepCount: 0, usage: .zero, cost: .zero, hasUnpricedSteps: false
    )

    public init(
        turnCount: Int,
        stepCount: Int,
        usage: TokenUsage,
        cost: Money<USD>,
        hasUnpricedSteps: Bool
    ) {
        self.turnCount = turnCount
        self.stepCount = stepCount
        self.usage = usage
        self.cost = cost
        self.hasUnpricedSteps = hasUnpricedSteps
    }

    public init(turns: [UsageTurn]) {
        let steps = turns.flatMap(\.steps)
        self.init(
            turnCount: turns.count,
            stepCount: steps.count,
            usage: steps.map(\.usage).reduce(.zero, +),
            cost: steps.compactMap(\.cost).reduce(.zero, +),
            hasUnpricedSteps: steps.contains { $0.cost == nil }
        )
    }

    /// How much of the input was served from the prompt cache, 0...1.
    ///
    /// The share of a bill that caching is holding down — the number to watch when a prompt is
    /// being restructured to cache better.
    public var cacheHitRate: Double {
        guard usage.inputTokens > 0 else {
            return 0
        }
        return Double(usage.cacheReadTokens ?? 0) / Double(usage.inputTokens)
    }
}

// MARK: - UsageLedger

/// Records what a session spent, turn by turn and step by step.
///
/// Prices each step as it arrives, from the catalog it was given: the price sheet belongs to the
/// model, and looking it up later means guessing which model served a step after the fact.
@MainActor
@Observable
public final class UsageLedger {
    public private(set) var turns: [UsageTurn] = []

    private let catalog: ModelCatalog?

    /// - Parameter catalog: Where price sheets are looked up. Without one, steps are recorded with
    ///   no cost and the UI reports token counts only.
    public init(catalog: ModelCatalog? = nil) {
        self.catalog = catalog
    }

    public var totals: UsageTotals {
        UsageTotals(turns: turns)
    }

    /// The whole session split by category, each step priced by the model that served it.
    public var breakdown: TokenBreakdown {
        breakdown(of: turns.flatMap(\.steps))
    }

    /// One turn split by category, each step priced by the model that served it.
    public func breakdown(of turn: UsageTurn) -> TokenBreakdown {
        breakdown(of: turn.steps)
    }

    private func breakdown(of steps: [UsageStep]) -> TokenBreakdown {
        TokenBreakdown(
            combining: steps.map {
                TokenBreakdown(usage: $0.usage, pricing: pricing(forModelID: $0.modelID))
            }
        )
    }

    private func pricing(forModelID modelID: String) -> Pricing? {
        catalog?.models.first { $0.modelID == modelID }?.profile.pricing
    }

    /// Starts a turn. Steps recorded afterwards belong to it.
    public func startTurn(label: String? = nil) {
        turns.append(UsageTurn(index: turns.count + 1, label: label))
    }

    /// Records one model call.
    ///
    /// Starts a turn first when none is open, so a step is never dropped for arriving early — a
    /// dropped step silently under-reports the bill, which is worse than an unlabelled turn.
    public func record(usage: TokenUsage, modelID: String) {
        if turns.isEmpty {
            startTurn()
        }
        let step = UsageStep(
            index: turns[turns.count - 1].steps.count + 1,
            modelID: modelID,
            usage: usage,
            cost: cost(of: usage, modelID: modelID)
        )
        turns[turns.count - 1].steps.append(step)
    }

    public func clear() {
        turns.removeAll()
    }

    /// Prices one step, or answers `nil` when the model is not in the catalog or has no price sheet.
    private func cost(of usage: TokenUsage, modelID: String) -> Money<USD>? {
        pricing(forModelID: modelID).map { CostCalculator.cost(of: usage, with: $0) }
    }
}

// MARK: - TokenUsage arithmetic

public extension TokenUsage {
    static let zero = TokenUsage(inputTokens: 0, outputTokens: 0)

    /// Adds two usages, keeping a subset count `nil` only when neither side reported it.
    ///
    /// Treating a missing count as zero when the other side has one would turn "not reported" into
    /// "reported as none", and the UI would show a breakdown that does not add up.
    static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        func add(_ a: Int?, _ b: Int?) -> Int? {
            guard a != nil || b != nil else {
                return nil
            }
            return (a ?? 0) + (b ?? 0)
        }
        return TokenUsage(
            inputTokens: lhs.inputTokens + rhs.inputTokens,
            outputTokens: lhs.outputTokens + rhs.outputTokens,
            reasoningTokens: add(lhs.reasoningTokens, rhs.reasoningTokens),
            cacheReadTokens: add(lhs.cacheReadTokens, rhs.cacheReadTokens),
            cacheCreationTokens: add(lhs.cacheCreationTokens, rhs.cacheCreationTokens),
            cacheTier: lhs.cacheTier ?? rhs.cacheTier
        )
    }
}
