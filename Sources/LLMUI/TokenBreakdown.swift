import Foundation
import LLMClient

// MARK: - TokenCategory

/// The parts a token bill splits into.
///
/// One vocabulary for the whole package: the same order and the same colour wherever a breakdown
/// appears, so a reader learns "teal is cached" once rather than per screen.
public enum TokenCategory: String, CaseIterable, Sendable, Hashable, Identifiable {
    /// Input served from the prompt cache. Cheap, and usually the largest slice by count.
    case cacheRead
    /// Input written into the cache so a later call can read it.
    case cacheWrite
    /// Input that was neither read from nor written to the cache.
    case input
    /// Output the model showed.
    case output
    /// Output the model thought with but did not show.
    case reasoning

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .cacheRead: "cached"
        case .cacheWrite: "cache write"
        case .input: "input"
        case .output: "output"
        case .reasoning: "reasoning"
        }
    }

    /// Token count of this part.
    public func tokens(in usage: TokenUsage) -> Int {
        switch self {
        case .cacheRead: usage.cacheReadTokens ?? 0
        case .cacheWrite: usage.cacheCreationTokens ?? 0
        case .input: usage.freshInputTokens
        case .output: usage.visibleOutputTokens
        case .reasoning: usage.reasoningTokens ?? 0
        }
    }

    /// Rate per million tokens for this part, given a price sheet and the size of the input.
    ///
    /// Mirrors `CostCalculator`: a rate a price sheet leaves unset falls back to the tier's base
    /// rate, meaning "no discount" rather than "free".
    public func ratePerMTok(_ pricing: Pricing, inputTokens: Int, cacheTier: CacheTier?) -> Double {
        let tier = pricing.tier(forInputTokens: inputTokens)
        switch self {
        case .cacheRead:
            return pricing.cacheReadPerMTok ?? tier.inputPerMTok
        case .cacheWrite:
            switch cacheTier {
            case .long: return pricing.cacheWriteLongPerMTok ?? tier.inputPerMTok
            case .short, .none: return pricing.cacheWriteShortPerMTok ?? tier.inputPerMTok
            }
        case .input:
            return tier.inputPerMTok
        case .output:
            return tier.outputPerMTok
        case .reasoning:
            return pricing.reasoningPerMTok ?? tier.outputPerMTok
        }
    }
}

// MARK: - TokenBreakdown

/// A usage split into parts, by count and — when the price sheet is known — by cost.
///
/// The two splits are worth seeing together because they disagree: cached input can be most of the
/// tokens and almost none of the money. A bar of counts alone suggests the wrong thing to optimise.
public struct TokenBreakdown: Sendable, Hashable {
    public struct Slice: Sendable, Hashable, Identifiable {
        public let category: TokenCategory
        public let tokens: Int
        public let cost: Money<USD>?

        public var id: TokenCategory { category }
    }

    public let usage: TokenUsage

    /// Parts with a non-zero token count, in ``TokenCategory`` order.
    public let slices: [Slice]

    public let totalCost: Money<USD>?

    public init(usage: TokenUsage, pricing: Pricing? = nil) {
        self.usage = usage
        slices = TokenCategory.allCases.compactMap { category in
            let tokens = category.tokens(in: usage)
            guard tokens > 0 else {
                return nil
            }
            let cost = pricing.map { sheet -> Money<USD> in
                let rate = category.ratePerMTok(
                    sheet, inputTokens: usage.inputTokens, cacheTier: usage.cacheTier
                )
                return Money<USD>(Double(tokens) * rate / 1_000_000)
            }
            return Slice(category: category, tokens: tokens, cost: cost)
        }
        totalCost = pricing.map { CostCalculator.cost(of: usage, with: $0) }
    }

    /// Combines breakdowns that were each priced by their own model's sheet.
    ///
    /// A session can mix models, and there is no single sheet that prices all of it: charging a
    /// cheap model's tokens at an expensive model's rates is wrong exactly when the mixture is the
    /// interesting part. Adding up per-model breakdowns keeps every token at the rate it was
    /// actually billed at.
    ///
    /// The result is unpriced only when none of the parts were priced; a part with no sheet
    /// contributes its tokens and no cost, which is what ``UsageTotals/hasUnpricedSteps`` warns
    /// about.
    public init(combining breakdowns: [TokenBreakdown]) {
        usage = breakdowns.map(\.usage).reduce(.zero, +)

        var tokensByCategory: [TokenCategory: Int] = [:]
        var costByCategory: [TokenCategory: Money<USD>] = [:]
        for breakdown in breakdowns {
            for slice in breakdown.slices {
                tokensByCategory[slice.category, default: 0] += slice.tokens
                if let cost = slice.cost {
                    costByCategory[slice.category, default: .zero] = costByCategory[
                        slice.category, default: .zero
                    ] + cost
                }
            }
        }

        slices = TokenCategory.allCases.compactMap { category in
            guard let tokens = tokensByCategory[category], tokens > 0 else {
                return nil
            }
            return Slice(category: category, tokens: tokens, cost: costByCategory[category])
        }

        let totals = breakdowns.compactMap(\.totalCost)
        totalCost = totals.isEmpty ? nil : totals.reduce(.zero, +)
    }

    public var totalTokens: Int {
        slices.reduce(0) { $0 + $1.tokens }
    }

    /// Each slice's share of the token count, 0...1. Empty when nothing was counted.
    public var tokenShares: [(slice: Slice, share: Double)] {
        let total = totalTokens
        guard total > 0 else {
            return []
        }
        return slices.map { ($0, Double($0.tokens) / Double(total)) }
    }

    /// Each slice's share of the cost, 0...1. Empty when no price sheet was known.
    public var costShares: [(slice: Slice, share: Double)] {
        let priced = slices.compactMap { slice -> (Slice, Double)? in
            guard let cost = slice.cost, cost.value > 0 else {
                return nil
            }
            return (slice, cost.value)
        }
        let total = priced.reduce(0) { $0 + $1.1 }
        guard total > 0 else {
            return []
        }
        return priced.map { ($0.0, $0.1 / total) }
    }
}
