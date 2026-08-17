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
                id: "test:expensive",
                providerID: "test",
                modelID: "expensive-model",
                displayName: "Expensive",
                shortName: "Expensive",
                profile: ModelProfile(
                    summary: "",
                    modelFamily: "Test",
                    toolCallSupport: .excellent,
                    japaneseSupport: .excellent,
                    modalities: [.text],
                    pricing: .flat(inputPerMTok: 1000, outputPerMTok: 10_000)
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

    /// 1 つのモデルの料金表でセッション全体を割ると、混ざったときに嘘になる。
    /// 安いモデルのトークンを高いモデルの単価で塗ってしまうため。
    @Test("モデルが混ざっても、各ステップは自分の料金表で計算する")
    func aMixedSessionPricesEachStepWithItsOwnSheet() {
        let ledger = UsageLedger(catalog: makeCatalog())
        // 同じトークン数を、安いモデルと高いモデルで 1 回ずつ
        let usage = TokenUsage(inputTokens: 1_000_000, outputTokens: 0)
        ledger.record(usage: usage, modelID: "priced-model")     // $10
        ledger.record(usage: usage, modelID: "expensive-model")  // $1000

        #expect(ledger.totals.cost.value == 1010)

        // 費用の割合も、片方の単価で塗り直さない
        let inputSlice = ledger.breakdown.slices.first { $0.category == .input }
        #expect(inputSlice?.cost?.value == 1010)
        #expect(inputSlice?.tokens == 2_000_000)
    }

    /// 合計は「ステップごとに正しく出した費用」の和であって、
    /// 割合を出すために選んだ 1 枚の料金表からは作らない。
    @Test("内訳の合計は合計費用と一致する")
    func theBreakdownAddsUpToTheTotal() {
        let ledger = UsageLedger(catalog: makeCatalog())
        ledger.record(
            usage: TokenUsage(inputTokens: 500_000, outputTokens: 100_000, cacheReadTokens: 200_000),
            modelID: "priced-model"
        )
        ledger.record(
            usage: TokenUsage(inputTokens: 300_000, outputTokens: 50_000),
            modelID: "expensive-model"
        )

        let summed = ledger.breakdown.slices.compactMap(\.cost).reduce(Money<USD>.zero, +)
        #expect(abs(summed.value - ledger.totals.cost.value) < 0.000_001)
    }

    @Test("料金表が無いステップが混ざっても、分かる分だけ足す")
    func unpricedStepsDoNotBreakTheBreakdown() {
        let ledger = UsageLedger(catalog: makeCatalog())
        ledger.record(usage: TokenUsage(inputTokens: 1_000_000, outputTokens: 0), modelID: "priced-model")
        ledger.record(usage: TokenUsage(inputTokens: 1_000_000, outputTokens: 0), modelID: "unpriced-model")

        #expect(ledger.breakdown.slices.first { $0.category == .input }?.tokens == 2_000_000)
        #expect(ledger.totals.cost.value == 10)
        #expect(ledger.totals.hasUnpricedSteps)
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
