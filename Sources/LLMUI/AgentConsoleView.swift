#if canImport(SwiftUI)

    import Foundation
    import SwiftUI

    // MARK: - AgentConsoleView

    /// The console: pick what runs, hold the keys, read what happened.
    ///
    /// Laid out by the things there are — the model, the credentials, the run — rather than by the
    /// tasks one might do to them. Each is a row that opens onto that thing in full, so the top
    /// level answers "what is set up" at a glance and the depth is there when a question needs it.
    public struct AgentConsoleView: View {
        private let console: AgentConsole
        private let onCopy: ((String) -> Void)?
        private let extraSections: AnyView?

        @Environment(\.dismiss) private var dismiss

        /// - Parameters:
        ///   - console: What to show.
        ///   - onCopy: Puts text on the pasteboard. Omitted, the copy buttons are hidden.
        ///   - extraSections: Host-specific rows, added below the standard ones. For anything only
        ///     the app can explain — its own stored data, its own inspectors.
        public init(
            console: AgentConsole,
            onCopy: ((String) -> Void)? = nil,
            @ViewBuilder extraSections: () -> some View = { EmptyView() }
        ) {
            self.console = console
            self.onCopy = onCopy
            let sections = extraSections()
            self.extraSections = sections is EmptyView ? nil : AnyView(sections)
        }

        public var body: some View {
            List {
                providerSection
                instrumentSection
                extraSections
            }
            .navigationTitle("Agent")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
        }

        // MARK: Providers

        private var providerSection: some View {
            Section {
                ForEach(console.providers) { provider in
                    NavigationLink {
                        ProviderDetailView(provider: provider, console: console)
                    } label: {
                        ProviderRow(provider: provider, console: console)
                    }
                    .accessibilityIdentifier(AgentConsoleID.provider(provider.id))
                }
            } header: {
                Text("Providers")
            } footer: {
                Text(runsOn)
            }
        }

        /// Says what would run right now, in one line — including why it would not.
        private var runsOn: String {
            guard let model = console.selectedModel else {
                return "No model selected."
            }
            guard console.apiKey != nil else {
                let name = console.selectedProvider?.displayName ?? model.providerID
                return "\(model.displayName) is selected, but \(name) has no key."
            }
            let effort = console.reasoningEffort.map { ", thinking \($0.rawValue)" } ?? ""
            return "Runs \(model.displayName)\(effort)."
        }

        // MARK: Instruments

        private var instrumentSection: some View {
            Section {
                NavigationLink {
                    UsageView(
                        ledger: console.usage,
                        settings: console.costSettings,
                        onCopy: onCopy,
                        onRefreshRate: { await console.refreshExchangeRate() }
                    )
                    .navigationTitle("Usage")
                    #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                    #endif
                } label: {
                    LabeledContent("Usage") {
                        Text(usageSummary)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .accessibilityIdentifier(AgentConsoleID.usageRow)

                NavigationLink {
                    AgentTraceView(
                        log: console.trace,
                        emptyMessage: "Send a message and what the agent does lands here.",
                        onCopy: onCopy
                    )
                    .navigationTitle("Trace")
                    #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                    #endif
                } label: {
                    LabeledContent("Trace") {
                        Text(traceSummary)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .accessibilityIdentifier(AgentConsoleID.traceRow)

                Button("Clear instruments", role: .destructive) {
                    console.clearInstruments()
                }
                .disabled(console.trace.entries.isEmpty && console.usage.turns.isEmpty)
            } header: {
                Text("This session")
            }
        }

        /// How many runs, and whether any of them failed — the failure is the reason to look.
        private var traceSummary: String {
            let runs = console.trace.runs
            guard !runs.isEmpty else {
                return "—"
            }
            let failures = runs.count(where: \.hasFailure)
            let runText = runs.count == 1 ? "1 run" : "\(runs.count) runs"
            return failures > 0 ? "\(runText) · \(failures) failed" : runText
        }

        private var usageSummary: String {
            let totals = console.usage.totals
            guard totals.stepCount > 0 else {
                return "—"
            }
            return "\(totals.usage.totalTokens) · \(console.costSettings.format(totals.cost))"
        }
    }

    // MARK: - AgentConsoleID

    /// Names for the console's rows, so a test can find them without depending on wording.
    ///
    /// The labels are display text and will change. These will not.
    public enum AgentConsoleID {
        public static let usageRow = "console.usage"
        public static let traceRow = "console.trace"
        public static let useModel = "console.useModel"
        public static let effortPicker = "console.effort"
        public static let done = "console.done"

        public static func provider(_ providerID: String) -> String {
            "console.provider.\(providerID)"
        }

        public static func run(_ runID: UUID) -> String {
            "console.run.\(runID.uuidString)"
        }

        public static func credentialField(_ providerID: String) -> String {
            "console.credential.\(providerID)"
        }
    }

#endif
