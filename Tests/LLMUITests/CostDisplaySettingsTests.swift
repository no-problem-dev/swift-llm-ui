import Foundation
import LLMClient
import Testing

@testable import LLMUI

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
