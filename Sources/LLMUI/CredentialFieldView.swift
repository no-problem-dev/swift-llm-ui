#if canImport(SwiftUI)

    import LLMCloudBranding
    import SwiftUI

    // MARK: - CredentialFieldView

    /// One provider's API key: what is in effect, where it came from, and a field to change it.
    ///
    /// The badge is the point. A key can come from the environment or from the device, and when
    /// a call fails for auth the first question is which one was used — so the view says so
    /// rather than showing an anonymous filled-in field.
    public struct CredentialFieldView: View {
        private let provider: CredentialProvider
        private let resolver: CredentialResolver

        @State private var draft = ""
        @State private var isRevealed = false
        @State private var source = CredentialSource.missing

        public init(provider: CredentialProvider, resolver: CredentialResolver) {
            self.provider = provider
            self.resolver = resolver
        }

        private var trimmedDraft: String {
            draft.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    if let key = provider.brandKey, let brand = CloudProviderBrand(rawValue: key) {
                        CloudProviderLogo(brand, size: 14)
                    }
                    Text(provider.displayName)
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    badge
                }

                field
                actions
            }
            .padding(.vertical, 4)
            .onAppear(perform: reload)
        }

        private var field: some View {
            HStack {
                Group {
                    if isRevealed {
                        TextField(placeholder, text: $draft)
                    } else {
                        SecureField(placeholder, text: $draft)
                    }
                }
                .font(.caption.monospaced())
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif
                    .autocorrectionDisabled()

                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text(isRevealed ? "Hide key" : "Show key"))
            }
        }

        private var actions: some View {
            HStack {
                Button("Save") {
                    resolver.setKey(trimmedDraft, for: provider)
                    draft = ""
                    reload()
                }
                .disabled(trimmedDraft.isEmpty)

                Spacer()

                Button(role: .destructive) {
                    resolver.setKey(nil, for: provider)
                    draft = ""
                    reload()
                } label: {
                    Text("Remove saved key")
                }
                .disabled(source != .stored)
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }

        private var placeholder: String {
            provider.apiKeyEnvironmentVariable ?? "API key"
        }

        private var badge: some View {
            Text(badgeText)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(badgeColor.opacity(0.15), in: Capsule())
                .foregroundStyle(badgeColor)
        }

        private var badgeText: String {
            switch source {
            case .stored: "On device"
            case .environment: "Environment"
            case .missing: "Not set"
            }
        }

        private var badgeColor: Color {
            switch source {
            case .stored: .green
            case .environment: .blue
            case .missing: .secondary
            }
        }

        private func reload() {
            source = resolver.source(for: provider)
        }
    }

#endif
