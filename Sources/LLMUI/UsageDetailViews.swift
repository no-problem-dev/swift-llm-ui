#if canImport(SwiftUI)

    import LLMClient
    import SwiftUI

    // MARK: - UsageTurnView

    /// One turn: what it came to, and every model call inside it.
    public struct UsageTurnView: View {
        private let turn: UsageTurn
        private let breakdown: TokenBreakdown
        private let settings: CostDisplaySettings
        private let stepBreakdown: (UsageStep) -> TokenBreakdown

        public init(
            turn: UsageTurn,
            breakdown: TokenBreakdown,
            settings: CostDisplaySettings,
            stepBreakdown: @escaping (UsageStep) -> TokenBreakdown
        ) {
            self.turn = turn
            self.breakdown = breakdown
            self.settings = settings
            self.stepBreakdown = stepBreakdown
        }

        public var body: some View {
            List {
                Section {
                    UsageHeadline(
                        tokens: turn.usage.totalTokens,
                        cost: turn.cost,
                        settings: settings,
                        note: turn.hasUnpricedSteps ? "at least — some steps had no price sheet" : nil
                    )
                    TokenBreakdownView(breakdown, settings: settings)
                } header: {
                    Text(turn.label ?? "Turn \(turn.index)")
                }

                Section {
                    ForEach(turn.steps) { step in
                        NavigationLink {
                            UsageStepView(
                                step: step,
                                breakdown: stepBreakdown(step),
                                settings: settings
                            )
                        } label: {
                            UsageStepRow(step: step, settings: settings)
                        }
                    }
                } header: {
                    Text("\(turn.steps.count) model calls")
                }
            }
            .navigationTitle("Turn \(turn.index)")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    // MARK: - UsageStepView

    /// One model call in full.
    public struct UsageStepView: View {
        private let step: UsageStep
        private let breakdown: TokenBreakdown
        private let settings: CostDisplaySettings

        public init(step: UsageStep, breakdown: TokenBreakdown, settings: CostDisplaySettings) {
            self.step = step
            self.breakdown = breakdown
            self.settings = settings
        }

        public var body: some View {
            List {
                Section {
                    UsageHeadline(
                        tokens: step.usage.totalTokens,
                        cost: step.cost,
                        settings: settings,
                        note: step.cost == nil ? "no price sheet for this model" : nil
                    )
                    TokenBreakdownView(breakdown, settings: settings)
                }

                Section {
                    DebugRow("Model", step.modelID)
                    DebugRow("At", step.at.formatted(date: .omitted, time: .standard))
                } header: {
                    Text("Call")
                }

                Section {
                    DebugRow("Input", "\(step.usage.inputTokens)")
                    DebugRow("Output", "\(step.usage.outputTokens)")
                    if let reasoning = step.usage.reasoningTokens {
                        DebugRow("Reasoning", "\(reasoning)")
                    }
                    if let cacheRead = step.usage.cacheReadTokens {
                        DebugRow("Cache read", "\(cacheRead)", accent: .teal)
                    }
                    if let cacheWrite = step.usage.cacheCreationTokens {
                        DebugRow("Cache write", "\(cacheWrite)")
                    }
                    if let tier = step.usage.cacheTier {
                        DebugRow("Cache tier", tier.rawValue)
                    }
                } header: {
                    Text("Tokens as reported")
                } footer: {
                    Text(
                        "Cached and written input are counted inside the input total; reasoning is "
                            + "counted inside the output total."
                    )
                }
            }
            .navigationTitle("Step \(step.index)")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    // MARK: - UsageHeadline

    /// The number and the money, side by side.
    struct UsageHeadline: View {
        let tokens: Int
        let cost: Money<USD>?
        let settings: CostDisplaySettings
        var note: String?

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(tokens)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("tokens")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if let cost {
                        Text(settings.format(cost))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.green)
                    }
                    if let note {
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
    }

#endif
