#if canImport(SwiftUI)

    import LLMClient
    import LLMCloudBranding
    import SwiftUI

    // MARK: - ProviderDetailView

    /// One provider: its key, and the models it serves.
    ///
    /// A key and a model list are two things about the same provider, and separating them means
    /// answering "can I use this?" takes two screens. Here the key sits above the models it
    /// unlocks, so the reason to set it is visible from where it is set.
    public struct ProviderDetailView: View {
        private let provider: CredentialProvider
        private let console: AgentConsole

        public init(provider: CredentialProvider, console: AgentConsole) {
            self.provider = provider
            self.console = console
        }

        private var models: [ModelDescriptor] {
            console.catalog.models(providerID: provider.id)
        }

        public var body: some View {
            List {
                Section {
                    CredentialFieldView(provider: provider, resolver: console.credentials)
                        .accessibilityIdentifier(AgentConsoleID.credentialField(provider.id))
                } header: {
                    Text("API key")
                } footer: {
                    if console.credentials.key(for: provider) == nil {
                        Text("Models below cannot run until this is set.")
                    }
                }

                Section {
                    ForEach(models) { model in
                        NavigationLink {
                            ModelDetailView(
                                model: model,
                                providerName: provider.displayName,
                                console: console
                            )
                        } label: {
                            row(model)
                        }
                    }
                } header: {
                    Text("Models")
                }
            }
            .navigationTitle(provider.displayName)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
        }

        private func row(_ model: ModelDescriptor) -> some View {
            let isSelected = model.id == console.selectedModelID
            return HStack(alignment: .top, spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                    Text(model.profile.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        if let window = model.contextWindowText {
                            Text(window)
                        }
                        if let price = model.entryPriceText {
                            Text(price)
                        }
                    }
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - ProviderRow

    /// A provider as it appears in a list: name, logo, key state, how many models.
    public struct ProviderRow: View {
        private let provider: CredentialProvider
        private let console: AgentConsole

        public init(provider: CredentialProvider, console: AgentConsole) {
            self.provider = provider
            self.console = console
        }

        public var body: some View {
            HStack(spacing: 8) {
                if let key = provider.brandKey, let brand = CloudProviderBrand(rawValue: key) {
                    CloudProviderLogo(brand, size: 20)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(provider.displayName)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if isSelected {
                    Text("in use")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }

        private var isSelected: Bool {
            console.selectedProvider?.id == provider.id
        }

        private var subtitle: String {
            let count = console.catalog.models(providerID: provider.id).count
            let source = console.credentials.source(for: provider)
            let key: String
            switch source {
            case .stored: key = "key on device"
            case .environment: key = "key from environment"
            case .missing: key = "no key"
            }
            return "\(count) models · \(key)"
        }
    }

#endif
