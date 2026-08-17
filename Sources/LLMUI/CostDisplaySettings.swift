import Foundation
import LLMClient
import Observation

// MARK: - CostDisplayCurrency

public enum CostDisplayCurrency: String, CaseIterable, Identifiable, Sendable {
    case usd
    case jpy

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .usd: "USD ($)"
        case .jpy: "JPY (¥)"
        }
    }
}

// MARK: - CostDisplaySettings

/// How costs are shown: in which currency, and at what scale.
///
/// One turn of a cheap model costs a fraction of a cent, which reads as `$0.0000` and tells you
/// nothing. The multiplier answers the question actually being asked — *what would this cost if
/// it ran ten thousand times* — without pretending the measured number is bigger than it is.
@MainActor
@Observable
public final class CostDisplaySettings {
    /// Scales offered for "what if this ran N times".
    public static let multipliers = [1, 10, 100, 1000, 10_000]

    /// Used when no rate has ever been fetched, so a yen figure is still roughly right.
    public static let fallbackUSDJPYRate = ExchangeRate<USD, JPY>(150, asOf: .distantPast)

    /// How old a rate may be before it is called stale. A day: FX moves, but not enough to make
    /// a debug cost estimate wrong.
    public static let freshnessWindow: TimeInterval = 60 * 60 * 24

    public var currency: CostDisplayCurrency {
        didSet { defaults.set(currency.rawValue, forKey: Key.currency) }
    }

    public var multiplier: Int {
        didSet { defaults.set(multiplier, forKey: Key.multiplier) }
    }

    public private(set) var rate: ExchangeRate<USD, JPY>?

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        currency = defaults.string(forKey: Key.currency)
            .flatMap(CostDisplayCurrency.init(rawValue:)) ?? .usd

        let storedMultiplier = defaults.integer(forKey: Key.multiplier)
        multiplier = Self.multipliers.contains(storedMultiplier) ? storedMultiplier : 1

        let value = defaults.double(forKey: Key.rateValue)
        let asOf = defaults.double(forKey: Key.rateAsOf)
        rate = (value > 0 && asOf > 0)
            ? ExchangeRate(value, asOf: Date(timeIntervalSince1970: asOf))
            : nil
    }

    public func update(rate: ExchangeRate<USD, JPY>) {
        self.rate = rate
        defaults.set(rate.value, forKey: Key.rateValue)
        defaults.set(rate.asOf.timeIntervalSince1970, forKey: Key.rateAsOf)
    }

    /// The stored rate, or `nil` when it is missing or older than ``freshnessWindow``.
    public var freshRate: ExchangeRate<USD, JPY>? {
        guard let rate, Date().timeIntervalSince(rate.asOf) < Self.freshnessWindow else {
            return nil
        }
        return rate
    }

    /// The rate to convert with: the fresh one, else a stale one, else the fallback.
    ///
    /// Always answers, so a yen figure never disappears because the network was down. Whether it
    /// is trustworthy is a separate question — read ``freshRate`` to decide what to tell the user.
    public var effectiveRate: ExchangeRate<USD, JPY> {
        freshRate ?? rate ?? Self.fallbackUSDJPYRate
    }

    // MARK: - Formatting

    /// Formats a cost in the chosen currency, scaled by the multiplier.
    public func format(_ cost: Money<USD>) -> String {
        let scaled = cost * Double(multiplier)
        switch currency {
        case .usd:
            return scaled.formatted()
        case .jpy:
            return Self.formatYen(scaled.converted(to: JPY.self, rate: effectiveRate))
        }
    }

    /// Says what the multiplier means, or nothing when it is 1.
    public var multiplierNote: String? {
        multiplier == 1 ? nil : "×\(multiplier.formatted()) — the same work run \(multiplier.formatted()) times"
    }

    /// Yen with enough decimals to stay meaningful.
    ///
    /// A single cheap turn is well under one yen, and the currency's usual zero decimals would
    /// round it to `¥0`. Below ¥10 the amount keeps roughly two significant digits instead.
    static func formatYen(_ money: Money<JPY>) -> String {
        let amount = abs(money.value)
        guard amount > 0, amount < 10 else {
            return money.formatted(minimumFractionDigits: 0, maximumFractionDigits: 0)
        }
        let leadingZeros = max(0, Int(-floor(log10(amount))) - 1)
        let digits = leadingZeros + 2
        return money.formatted(minimumFractionDigits: digits, maximumFractionDigits: digits)
    }

    private enum Key {
        static let currency = "LLMUI.cost.currency"
        static let multiplier = "LLMUI.cost.multiplier"
        static let rateValue = "LLMUI.cost.usdJpyRate.value"
        static let rateAsOf = "LLMUI.cost.usdJpyRate.asOf"
    }
}
