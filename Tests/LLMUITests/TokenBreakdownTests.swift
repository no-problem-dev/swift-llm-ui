import Foundation
import LLMClient
import Testing

@testable import LLMUI

/// 使ったトークンを、量と費用の 2 通りに割る。
@Suite("Token breakdown")
struct TokenBreakdownTests {

    /// 入力の総量にはキャッシュ分が含まれる。素の入力として二重に数えない。
    @Test("キャッシュ分は入力から取り分ける")
    func cachedTokensAreTakenOutOfInput() {
        let usage = TokenUsage(
            inputTokens: 1000,
            outputTokens: 100,
            cacheReadTokens: 700,
            cacheCreationTokens: 100
        )
        let breakdown = TokenBreakdown(usage: usage)

        let byCategory = Dictionary(
            uniqueKeysWithValues: breakdown.slices.map { ($0.category, $0.tokens) }
        )
        #expect(byCategory[.cacheRead] == 700)
        #expect(byCategory[.cacheWrite] == 100)
        #expect(byCategory[.input] == 200)
        #expect(breakdown.totalTokens == 1100)
    }

    /// 思考は出力の内側。見えた出力として二重に数えない。
    @Test("思考は出力から取り分ける")
    func reasoningIsTakenOutOfOutput() {
        let usage = TokenUsage(inputTokens: 10, outputTokens: 100, reasoningTokens: 40)
        let byCategory = Dictionary(
            uniqueKeysWithValues: TokenBreakdown(usage: usage).slices.map { ($0.category, $0.tokens) }
        )

        #expect(byCategory[.output] == 60)
        #expect(byCategory[.reasoning] == 40)
    }

    @Test("0 の区画は出さない")
    func emptySlicesAreDropped() {
        let breakdown = TokenBreakdown(usage: TokenUsage(inputTokens: 10, outputTokens: 5))

        #expect(breakdown.slices.map(\.category) == [.input, .output])
    }

    @Test("区画の並びはいつも同じ")
    func slicesKeepACanonicalOrder() {
        let usage = TokenUsage(
            inputTokens: 100,
            outputTokens: 100,
            reasoningTokens: 10,
            cacheReadTokens: 30,
            cacheCreationTokens: 20
        )

        #expect(
            TokenBreakdown(usage: usage).slices.map(\.category)
                == [.cacheRead, .cacheWrite, .input, .output, .reasoning]
        )
    }

    /// 量では大きいキャッシュが、費用ではほぼ消える — 2 本並べる理由がこれ。
    @Test("量の割合と費用の割合は一致しない")
    func tokenSharesAndCostSharesDisagree() {
        let pricing = Pricing.flat(
            inputPerMTok: 10,
            outputPerMTok: 100,
            cacheReadPerMTok: 1
        )
        let usage = TokenUsage(inputTokens: 1000, outputTokens: 100, cacheReadTokens: 900)
        let breakdown = TokenBreakdown(usage: usage, pricing: pricing)

        let cachedTokenShare = breakdown.tokenShares
            .first { $0.slice.category == .cacheRead }?.share ?? 0
        let cachedCostShare = breakdown.costShares
            .first { $0.slice.category == .cacheRead }?.share ?? 0

        #expect(cachedTokenShare > 0.8)
        #expect(cachedCostShare < 0.1)
    }

    @Test("料金表が無ければ費用の割合は空")
    func costSharesAreEmptyWithoutPricing() {
        let breakdown = TokenBreakdown(usage: TokenUsage(inputTokens: 10, outputTokens: 10))

        #expect(breakdown.costShares.isEmpty)
        #expect(breakdown.totalCost == nil)
    }

    /// 区画ごとの費用を足したものが、CostCalculator の答えと合う。
    @Test("区画の費用の合計は総額と一致する")
    func sliceCostsSumToTheTotal() {
        let pricing = Pricing.flat(
            inputPerMTok: 10,
            outputPerMTok: 100,
            cacheReadPerMTok: 1
        )
        let usage = TokenUsage(
            inputTokens: 500_000,
            outputTokens: 200_000,
            reasoningTokens: 50_000,
            cacheReadTokens: 300_000
        )
        let breakdown = TokenBreakdown(usage: usage, pricing: pricing)

        let summed = breakdown.slices.compactMap(\.cost).reduce(Money<USD>.zero, +)
        let total = try! #require(breakdown.totalCost)

        #expect(abs(summed.value - total.value) < 0.000_001)
    }

    @Test("割合は 1 に合う")
    func sharesAddUpToOne() {
        let usage = TokenUsage(
            inputTokens: 1000,
            outputTokens: 500,
            reasoningTokens: 100,
            cacheReadTokens: 400
        )
        let total = TokenBreakdown(usage: usage).tokenShares.reduce(0) { $0 + $1.share }

        #expect(abs(total - 1.0) < 0.000_001)
    }
}

/// 費用の見せ方。通貨と倍率。
@MainActor
@Suite("Cost display")
struct CostDisplaySettingsTests {

    private func makeSettings(_ name: String) -> CostDisplaySettings {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return CostDisplaySettings(defaults: defaults)
    }

    @Test("倍率は表示にだけ効く")
    func theMultiplierScalesTheDisplay() {
        let settings = makeSettings(#function)
        settings.multiplier = 1000

        #expect(settings.format(Money<USD>(0.0001)).contains("0.1"))
        #expect(settings.multiplierNote != nil)
    }

    @Test("倍率 1 のときは注記を出さない")
    func noNoteAtScaleOne() {
        #expect(makeSettings(#function).multiplierNote == nil)
    }

    /// 1 円未満を ¥0 に丸めると、安いモデルの費用が全部 0 に見える。
    @Test("1 円未満でも有効数字を残す")
    func subYenAmountsKeepSignificantDigits() {
        let settings = makeSettings(#function)
        settings.currency = .jpy
        settings.update(rate: ExchangeRate(150))

        // $0.0001 = ¥0.015
        let formatted = settings.format(Money<USD>(0.0001))
        #expect(formatted.contains("0.015"))
    }

    @Test("大きい額は小数を出さない")
    func largeYenAmountsAreWhole() {
        let settings = makeSettings(#function)
        settings.currency = .jpy
        settings.update(rate: ExchangeRate(150))

        #expect(settings.format(Money<USD>(1)) == "¥150")
    }

    @Test("古いレートは fresh から外れるが、換算には使う")
    func aStaleRateStillConverts() {
        let settings = makeSettings(#function)
        let old = Date().addingTimeInterval(-CostDisplaySettings.freshnessWindow - 60)
        settings.update(rate: ExchangeRate(200, asOf: old))

        #expect(settings.freshRate == nil)
        #expect(settings.effectiveRate.value == 200)
    }

    @Test("レートが無ければ既定値で換算する")
    func withoutARateTheFallbackIsUsed() {
        let settings = makeSettings(#function)

        #expect(settings.rate == nil)
        #expect(settings.effectiveRate.value == CostDisplaySettings.fallbackUSDJPYRate.value)
    }

    @Test("通貨と倍率は残る")
    func choicesArePersisted() {
        let name = #function
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)

        let first = CostDisplaySettings(defaults: defaults)
        first.currency = .jpy
        first.multiplier = 100

        let second = CostDisplaySettings(defaults: defaults)
        #expect(second.currency == .jpy)
        #expect(second.multiplier == 100)
    }

    /// 一覧に無い倍率が残っていても、ピッカーが空を選んだ状態にならないようにする。
    @Test("知らない倍率は 1 に落とす")
    func anUnknownMultiplierFallsBackToOne() {
        let name = #function
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set(7, forKey: "LLMUI.cost.multiplier")

        #expect(CostDisplaySettings(defaults: defaults).multiplier == 1)
    }
}
