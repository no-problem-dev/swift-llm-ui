#if canImport(SwiftUI)

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
                modelSection
                credentialsSection
                instrumentSection
                extraSections
            }
            .navigationTitle("Agent")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
        }

        // MARK: Model

        private var modelSection: some View {
            Section {
                NavigationLink {
                    ModelPickerView(
                        catalog: console.catalog,
                        selectedModelID: Binding(
                            get: { console.selectedModelID },
                            set: { console.selectedModelID = $0 }
                        ),
                        providerNames: console.providerNames
                    )
                    .navigationTitle("Model")
                    #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                    #endif
                } label: {
                    LabeledContent("Model") {
                        Text(console.selectedModel?.displayName ?? console.selectedModelID)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier(AgentConsoleID.modelRow)
            } header: {
                Text("Runs on")
            } footer: {
                if let model = console.selectedModel {
                    Text(model.profile.summary)
                }
            }
        }

        // MARK: Credentials

        private var credentialsSection: some View {
            Section {
                NavigationLink {
                    CredentialsView(console: console)
                } label: {
                    LabeledContent("API keys") {
                        Text(credentialSummary)
                            .foregroundStyle(hasKeyForSelectedModel ? Color.secondary : Color.red)
                    }
                }
                .accessibilityIdentifier(AgentConsoleID.credentialsRow)
            } footer: {
                if !hasKeyForSelectedModel, let provider = console.selectedProvider {
                    Text("No key for \(provider.displayName). Runs will fail until one is set.")
                }
            }
        }

        private var hasKeyForSelectedModel: Bool {
            console.apiKey != nil
        }

        private var credentialSummary: String {
            let set = console.providers.filter { console.credentials.key(for: $0) != nil }.count
            return "\(set) of \(console.providers.count)"
        }

        // MARK: Instruments

        private var instrumentSection: some View {
            Section {
                NavigationLink {
                    UsageView(
                        ledger: console.usage,
                        settings: console.costSettings,
                        catalog: console.catalog,
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
                        Text("\(console.trace.entries.count)")
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
        public static let modelRow = "console.model"
        public static let credentialsRow = "console.credentials"
        public static let usageRow = "console.usage"
        public static let traceRow = "console.trace"
        public static let done = "console.done"

        public static func credentialField(_ providerID: String) -> String {
            "console.credential.\(providerID)"
        }
    }

#endif
