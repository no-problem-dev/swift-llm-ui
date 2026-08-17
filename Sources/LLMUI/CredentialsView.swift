#if canImport(SwiftUI)

    import SwiftUI

    // MARK: - CredentialsView

    /// Every provider's key on one screen.
    ///
    /// One page rather than a page per provider: the question being asked is almost always "which
    /// of these is set", and that is a comparison. Splitting them hides the answer behind taps.
    public struct CredentialsView: View {
        private let console: AgentConsole

        public init(console: AgentConsole) {
            self.console = console
        }

        public var body: some View {
            List {
                Section {
                    Text(
                        "Keys are read from this device first, then from the environment. "
                            + "A key saved here overrides one the process was launched with."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                ForEach(console.providers) { provider in
                    Section {
                        CredentialFieldView(provider: provider, resolver: console.credentials)
                            .accessibilityIdentifier(
                                AgentConsoleID.credentialField(provider.id)
                            )
                    } footer: {
                        Text(footnote(for: provider))
                    }
                }
            }
            .navigationTitle("API keys")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
        }

        /// Says which models this key unlocks, so it is clear why it is worth setting.
        private func footnote(for provider: CredentialProvider) -> String {
            let models = console.catalog.models(providerID: provider.id)
            guard !models.isEmpty else {
                return "No models from this provider are on offer."
            }
            let names = models.prefix(3).map(\.shortName).joined(separator: ", ")
            let rest = models.count > 3 ? " and \(models.count - 3) more" : ""
            return "Used by \(names)\(rest)."
        }
    }

#endif
