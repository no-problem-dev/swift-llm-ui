import AgentLoopKit
import Foundation
import LLMClient
import Observation

// MARK: - AgentConsole

/// Everything a debug console needs, in one place a screen can hold.
///
/// The parts are separately useful — a ledger without a picker, a trace without either — but they
/// are always wanted together and each has its own storage. Bundling them means a host builds one
/// object and passes it down, instead of threading four.
///
/// It owns no window state. Which sheet is open belongs to the screen showing it, and putting that
/// here is what makes two screens fight over one flag.
@MainActor
@Observable
public final class AgentConsole {
    /// The models on offer.
    public let catalog: ModelCatalog

    /// The providers whose keys this console can hold.
    public let providers: [CredentialProvider]

    /// How each provider's name is spelled in the picker.
    public let providerNames: [String: String]

    public let credentials: CredentialResolver
    public let usage: UsageLedger
    public let trace: AgentTraceLog
    public let costSettings: CostDisplaySettings

    private let exchangeRates: ExchangeRateService
    private let defaults: UserDefaults
    private let modelDefaultsKey: String
    private let effortDefaultsKey: String

    /// The chosen model, as a `ModelDescriptor.id`.
    ///
    /// Reading goes through the catalog, so a model that has since been retired answers as the
    /// default rather than as an id nothing can serve.
    public var selectedModelID: String {
        get { catalog.resolve(defaults.string(forKey: modelDefaultsKey)) }
        set { defaults.set(newValue, forKey: modelDefaultsKey) }
    }

    public var selectedModel: ModelDescriptor? {
        catalog.model(id: selectedModelID)
    }

    /// The provider that serves the chosen model.
    public var selectedProvider: CredentialProvider? {
        guard let providerID = selectedModel?.providerID else {
            return nil
        }
        return providers.first { $0.id == providerID }
    }

    /// The key to call the chosen model with, or `nil` when none is set.
    public var apiKey: String? {
        selectedProvider.flatMap(credentials.key(for:))
    }

    /// How hard the model should think, or `nil` to leave it to the model.
    ///
    /// Belongs to the model rather than the app: a model that cannot reason ignores it, and one
    /// that can will snap a tier it does not offer to the nearest it does.
    public var reasoningEffort: ReasoningEffort? {
        get {
            defaults.string(forKey: effortDefaultsKey)
                .flatMap(ReasoningEffort.init(rawValue:))
        }
        set { defaults.set(newValue?.rawValue ?? "", forKey: effortDefaultsKey) }
    }

    /// - Parameters:
    ///   - catalog: The models on offer.
    ///   - providers: The providers whose keys can be entered. Ids must match
    ///     `ModelDescriptor.providerID`, or a model's key will not be found.
    ///   - credentialStore: Where entered keys are kept.
    ///   - exchangeRates: Fetches the USD→JPY rate a yen figure is converted at.
    ///   - defaults: Where the model choice and cost preferences are kept.
    ///   - defaultsKeyPrefix: Namespaces this console's own stored settings, so two consoles in
    ///     one app do not overwrite each other.
    public init(
        catalog: ModelCatalog,
        providers: [CredentialProvider],
        credentialStore: any CredentialStoring = UserDefaultsCredentialStore(),
        exchangeRates: ExchangeRateService = ExchangeRateService(),
        defaults: UserDefaults = .standard,
        defaultsKeyPrefix: String = "LLMUI."
    ) {
        self.catalog = catalog
        self.providers = providers
        providerNames = Dictionary(
            uniqueKeysWithValues: providers.map { ($0.id, $0.displayName) }
        )
        credentials = CredentialResolver(store: credentialStore)
        usage = UsageLedger(catalog: catalog)
        trace = AgentTraceLog()
        costSettings = CostDisplaySettings(defaults: defaults)
        self.exchangeRates = exchangeRates
        self.defaults = defaults
        modelDefaultsKey = defaultsKeyPrefix + "selectedModel"
        effortDefaultsKey = defaultsKeyPrefix + "reasoningEffort"
    }

    /// Records one telemetry report: into the trace, and — for usage — into the ledger too.
    ///
    /// Pass this as the agent loop's sink and both instruments fill from the one stream, so a
    /// token count and the prompt that produced it cannot drift apart.
    public func record(_ telemetry: AgentTelemetry) {
        trace.record(telemetry)
        if case .usage(let tokens, let model) = telemetry {
            usage.record(usage: tokens, modelID: model)
        }
    }

    /// Marks the start of a turn, so what follows is grouped under it in both instruments.
    ///
    /// The ledger's turn and the trace's run are the same event seen twice — what it cost and what
    /// it did. Opening them together is what keeps the two from drifting apart.
    public func startTurn(label: String? = nil) {
        usage.startTurn(label: label)
        trace.beginRun(label: label)
    }

    /// Marks the end of a turn, so later entries are not attributed to it.
    public func endTurn() {
        trace.endRun()
    }

    /// Fetches a fresh USD→JPY rate.
    ///
    /// Failing is not worth interrupting anyone over — the stale or fallback rate keeps the yen
    /// figure readable — so the attempt is recorded in the trace and the answer is a Bool.
    @discardableResult
    public func refreshExchangeRate() async -> Bool {
        do {
            costSettings.update(rate: try await exchangeRates.fetchUSDJPY())
            return true
        } catch {
            trace.append(.failure, "exchange rate fetch failed", detail: "\(error)")
            return false
        }
    }

    /// Empties both instruments. They are read together, so they are cleared together.
    public func clearInstruments() {
        trace.clear()
        usage.clear()
    }
}
