#if canImport(SwiftUI)

    import LLMClient
    import SwiftUI

    // MARK: - UsageView

    /// What a session spent: the total, then a card per turn that opens to its steps.
    ///
    /// Three levels, each a real object rather than a formatting of the one above — session, turn,
    /// step. A turn is what the user asked for; a step is one model call, and a turn is often
    /// several because the model called tools. Totals alone hide that, which is exactly what you
    /// need to see when a single question costs more than it should.
    public struct UsageView: View {
        private let ledger: UsageLedger
        private let settings: CostDisplaySettings
        private let onCopy: ((String) -> Void)?
        private let onRefreshRate: (() async -> Void)?

        @State private var isRefreshingRate = false

        public init(
            ledger: UsageLedger,
            settings: CostDisplaySettings,
            onCopy: ((String) -> Void)? = nil,
            onRefreshRate: (() async -> Void)? = nil
        ) {
            self.ledger = ledger
            self.settings = settings
            self.onCopy = onCopy
            self.onRefreshRate = onRefreshRate
        }

        private var totals: UsageTotals { ledger.totals }

        public var body: some View {
            ScrollView {
                VStack(spacing: 12) {
                    CostSettingsCard(
                        settings: settings,
                        isRefreshing: $isRefreshingRate,
                        onRefresh: onRefreshRate
                    )

                    summary

                    if ledger.turns.isEmpty {
                        DebugEmptyHint(
                            "No model calls yet. Send a message and each turn's tokens land here."
                        )
                    } else {
                        ForEach(ledger.turns.reversed()) { turn in
                            NavigationLink {
                                UsageTurnView(
                                    turn: turn,
                                    breakdown: ledger.breakdown(of: turn),
                                    settings: settings,
                                    stepBreakdown: { ledger.breakdown(of: $0) }
                                )
                            } label: {
                                UsageTurnCard(
                                    turn: turn,
                                    breakdown: ledger.breakdown(of: turn),
                                    settings: settings
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(12)
            }
        }

        private var summary: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Session", systemImage: "sum")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if let onCopy {
                        CopyButton(text: transcript, onCopy: onCopy)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(totals.usage.totalTokens)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("tokens")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(settings.format(totals.cost))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.green)
                        if let note = costNote {
                            Text(note)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                TokenBreakdownView(ledger.breakdown, settings: settings)

                HStack(spacing: 16) {
                    DebugMetric("turns", "\(totals.turnCount)")
                    DebugMetric("steps", "\(totals.stepCount)")
                    DebugMetric(
                        "cache hit",
                        "\(Int((totals.cacheHitRate * 100).rounded()))%",
                        tint: totals.cacheHitRate > 0 ? .teal : nil
                    )
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.debugCardBackground)
            )
        }

        /// Says what the cost figure is, when it is not simply "what this session cost".
        private var costNote: String? {
            if totals.hasUnpricedSteps {
                return "at least — some steps had no price sheet"
            }
            return settings.multiplierNote ?? "estimated"
        }

        private func transcript() -> String {
            var lines = [
                "SESSION \(totals.usage.totalTokens) tokens / \(settings.format(totals.cost))",
                "turns=\(totals.turnCount) steps=\(totals.stepCount) "
                    + "cacheHit=\(Int((totals.cacheHitRate * 100).rounded()))%",
            ]
            for turn in ledger.turns {
                lines.append("")
                lines.append("--- Turn \(turn.index)\(turn.label.map { ": \($0)" } ?? "") ---")
                lines.append("  \(turn.usage.totalTokens) tokens / \(settings.format(turn.cost))")
                for step in turn.steps {
                    let cost = step.cost.map(settings.format) ?? "n/a"
                    lines.append(
                        "  #\(step.index) \(step.modelID) "
                            + "in=\(step.usage.inputTokens) out=\(step.usage.outputTokens) "
                            + "total=\(step.usage.totalTokens) cost=\(cost)"
                    )
                }
            }
            return lines.joined(separator: "\n")
        }
    }

    // MARK: - UsageTurnCard

    /// One turn as a row: what it came to, and how it split.
    struct UsageTurnCard: View {
        let turn: UsageTurn
        let breakdown: TokenBreakdown
        let settings: CostDisplaySettings

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Turn \(turn.index)")
                            .font(.subheadline.weight(.semibold))
                        if let label = turn.label {
                            Text(label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if !turn.modelIDs.isEmpty {
                            Text(turn.modelIDs.joined(separator: ", "))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(turn.usage.totalTokens)")
                            .font(.headline.monospacedDigit())
                        Text(settings.format(turn.cost))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.green)
                        Text("\(turn.steps.count) steps")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                TokenBreakdownView(breakdown, settings: settings, isCompact: true)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.debugCardBackground)
            )
        }
    }

    // MARK: - UsageStepRow

    /// One model call inside a turn.
    struct UsageStepRow: View {
        let step: UsageStep
        let settings: CostDisplaySettings

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("#\(step.index)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(step.modelID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("\(step.usage.totalTokens)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                }

                HStack(spacing: 10) {
                    ForEach(TokenBreakdown(usage: step.usage).slices) { slice in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(slice.category.color)
                                .frame(width: 6, height: 6)
                            Text("\(slice.category.label) \(slice.tokens)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 4)
                    if let cost = step.cost {
                        Text(settings.format(cost))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.green)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - CostSettingsCard

    /// Currency, scale, and the rate a yen figure is converted at.
    struct CostSettingsCard: View {
        @Bindable var settings: CostDisplaySettings
        @Binding var isRefreshing: Bool
        let onRefresh: (() async -> Void)?

        var body: some View {
            DebugCard("Cost display", systemImage: "slider.horizontal.3") {
                HStack {
                    Text("Currency")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("Currency", selection: $settings.currency) {
                        ForEach(CostDisplayCurrency.allCases) { currency in
                            Text(currency.displayName).tag(currency)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 180)
                }

                HStack {
                    Text("Scale")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("Scale", selection: $settings.multiplier) {
                        ForEach(CostDisplaySettings.multipliers, id: \.self) { value in
                            Text("×\(value.formatted())").tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                if settings.currency == .jpy {
                    rateBanner
                }
            }
        }

        private var rateBanner: some View {
            let isFresh = settings.freshRate != nil
            return HStack(spacing: 8) {
                Image(systemName: isFresh ? "yensign.circle" : "exclamationmark.triangle")
                    .foregroundStyle(isFresh ? Color.secondary : Color.orange)

                VStack(alignment: .leading, spacing: 1) {
                    Text(String(format: "1 USD = %.2f JPY", settings.effectiveRate.value))
                        .font(.caption.monospacedDigit())
                    Text(rateAge)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                if let onRefresh {
                    Button {
                        Task {
                            isRefreshing = true
                            await onRefresh()
                            isRefreshing = false
                        }
                    } label: {
                        if isRefreshing {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(isRefreshing)
                    .accessibilityLabel(Text("Refresh rate"))
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.debugCardBackground)
            )
        }

        private var rateAge: String {
            guard settings.rate != nil else {
                return "never fetched — showing a default"
            }
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            let ago = formatter.localizedString(for: settings.effectiveRate.asOf, relativeTo: Date())
            return settings.freshRate == nil ? "\(ago) — stale" : ago
        }
    }

#endif
