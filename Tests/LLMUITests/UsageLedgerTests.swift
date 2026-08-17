import Foundation
import LLMClient
import Testing

@testable import LLMUI

private let pricing = Pricing.flat(
    inputPerMTok: 10,
    outputPerMTok: 100,
    cacheReadPerMTok: 1
)

private func makeCatalog() -> ModelCatalog {
    ModelCatalog(
        models: [
            ModelDescriptor(
                id: "test:priced",
                providerID: "test",
                modelID: "priced-model",
                displayName: "Priced",
                shortName: "Priced",
                profile: ModelProfile(
                    summary: "",
                    modelFamily: "Test",
                    toolCallSupport: .excellent,
                    japaneseSupport: .excellent,
                    modalities: [.text],
                    pricing: pricing
                )
            ),
            ModelDescriptor(
                id: "test:unpriced",
                providerID: "test",
                modelID: "unpriced-model",
                displayName: "Unpriced",
                shortName: "Unpriced",
                profile: ModelProfile(
                    summary: "",
                    modelFamily: "Test",
                    toolCallSupport: .excellent,
                    japaneseSupport: .excellent,
                    modalities: [.text]
                )
            ),
        ],
        defaultModelID: "test:priced"
    )
}

/// 使ったトークンと費用を、ターンとステップに積む。
@MainActor
@Suite("Usage ledger")
struct UsageLedgerTests {

    @Test("ステップはいま開いているターンに積まれる")
    func stepsGoIntoTheOpenTurn() {
        let ledger = UsageLedger(catalog: makeCatalog())
        ledger.startTurn(label: "first")
        ledger.record(usage: TokenUsage(inputTokens: 10, outputTokens: 5), modelID: "priced-model")
        ledger.record(usage: TokenUsage(inputTokens: 20, outputTokens: 5), modelID: "priced-model")
        ledger.startTurn(label: "second")
        ledger.record(usage: TokenUsage(inputTokens: 30, outputTokens: 5), modelID: "priced-model")

        #expect(ledger.turns.count == 2)
        #expect(ledger.turns[0].steps.count == 2)
        #expect(ledger.turns[1].steps.count == 1)
        #expect(ledger.turns[0].steps.map(\.index) == [1, 2])
    }

    /// 落とすと請求が黙って減る。ラベルの無いターンのほうがまだよい。
    @Test("ターンより先に来たステップも落とさない")
    func aStepBeforeAnyTurnStillLands() {
        let ledger = UsageLedger(catalog: makeCatalog())
        ledger.record(usage: TokenUsage(inputTokens: 10, outputTokens: 5), modelID: "priced-model")

        #expect(ledger.turns.count == 1)
        #expect(ledger.turns[0].steps.count == 1)
        #expect(ledger.turns[0].label == nil)
    }

    @Test("費用はカタログの料金表から出す")
    func costComesFromTheCatalog() {
        let ledger = UsageLedger(catalog: makeCatalog())
        // 入力 1M・出力 1M ちょうどにして、料金表の数字がそのまま出ることを見る
        ledger.record(
            usage: TokenUsage(inputTokens: 1_000_000, outputTokens: 1_000_000),
            modelID: "priced-model"
        )

        #expect(ledger.turns[0].steps[0].cost?.value == 110)
    }

    /// 0 円ではなく「分からない」。合計から外して、UI がそう言えるようにする。
    @Test("料金表が無いモデルは費用なしで積む")
    func anUnpricedModelHasNoCost() {
        let ledger = UsageLedger(catalog: makeCatalog())
        ledger.record(usage: TokenUsage(inputTokens: 100, outputTokens: 100), modelID: "unpriced-model")

        #expect(ledger.turns[0].steps[0].cost == nil)
        #expect(ledger.totals.hasUnpricedSteps)
        #expect(ledger.totals.cost == .zero)
    }

    @Test("カタログが無ければ費用は出さない")
    func withoutACatalogNothingIsPriced() {
        let ledger = UsageLedger()
        ledger.record(usage: TokenUsage(inputTokens: 100, outputTokens: 100), modelID: "priced-model")

        #expect(ledger.turns[0].steps[0].cost == nil)
    }

    @Test("合計はターンとステップを畳んだもの")
    func totalsFoldEverything() {
        let ledger = UsageLedger(catalog: makeCatalog())
        ledger.startTurn()
        ledger.record(usage: TokenUsage(inputTokens: 100, outputTokens: 10), modelID: "priced-model")
        ledger.startTurn()
        ledger.record(usage: TokenUsage(inputTokens: 200, outputTokens: 20), modelID: "priced-model")

        let totals = ledger.totals
        #expect(totals.turnCount == 2)
        #expect(totals.stepCount == 2)
        #expect(totals.usage.inputTokens == 300)
        #expect(totals.usage.outputTokens == 30)
        #expect(!totals.hasUnpricedSteps)
    }

    @Test("同じターンに出てきたモデルは 1 回だけ並べる")
    func modelIDsAreDeduplicatedInOrder() {
        let ledger = UsageLedger(catalog: makeCatalog())
        ledger.startTurn()
        for modelID in ["priced-model", "unpriced-model", "priced-model"] {
            ledger.record(usage: TokenUsage(inputTokens: 1, outputTokens: 1), modelID: modelID)
        }

        #expect(ledger.turns[0].modelIDs == ["priced-model", "unpriced-model"])
    }

    @Test("キャッシュ率は入力に対する割合")
    func cacheHitRateIsAShareOfInput() {
        let ledger = UsageLedger(catalog: makeCatalog())
        ledger.record(
            usage: TokenUsage(inputTokens: 1000, outputTokens: 10, cacheReadTokens: 750),
            modelID: "priced-model"
        )

        #expect(ledger.totals.cacheHitRate == 0.75)
    }

    @Test("何も無いときのキャッシュ率は 0")
    func cacheHitRateIsZeroWhenEmpty() {
        #expect(UsageTotals.zero.cacheHitRate == 0)
    }
}

/// 足し算で「報告されなかった」を「0 と報告された」に変えない。
@Suite("Token usage arithmetic")
struct TokenUsageArithmeticTests {

    @Test("内訳は両方 nil のときだけ nil のまま")
    func subsetsStayNilOnlyWhenNeitherSideReported() {
        let reported = TokenUsage(inputTokens: 10, outputTokens: 10, reasoningTokens: 3)
        let silent = TokenUsage(inputTokens: 10, outputTokens: 10)

        #expect((silent + silent).reasoningTokens == nil)
        #expect((reported + silent).reasoningTokens == 3)
        #expect((reported + reported).reasoningTokens == 6)
    }

    @Test("合計は素直に足す")
    func totalsAddUp() {
        let sum = TokenUsage(inputTokens: 10, outputTokens: 20)
            + TokenUsage(inputTokens: 5, outputTokens: 7)

        #expect(sum.inputTokens == 15)
        #expect(sum.outputTokens == 27)
        #expect(sum.totalTokens == 42)
    }
}
