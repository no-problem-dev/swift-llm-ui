#if canImport(SwiftUI)

    import LLMClient
    import SwiftUI

    // MARK: - ModelDetailView

    /// Everything a ``ModelDescriptor`` knows, for deciding between two models that look alike in
    /// a list.
    public struct ModelDetailView: View {
        private let model: ModelDescriptor
        private let providerName: String

        @Environment(\.dismiss) private var dismiss

        public init(model: ModelDescriptor, providerName: String) {
            self.model = model
            self.providerName = providerName
        }

        public var body: some View {
            NavigationStack {
                List {
                    facts
                    description
                    strengths
                    bestFor
                    pricing
                }
                .navigationTitle(model.displayName)
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { dismiss() }
                        }
                    }
            }
        }

        @ViewBuilder
        private var facts: some View {
            Section {
                LabeledContent("Provider", value: providerName)
                LabeledContent("Model ID", value: model.modelID)
                LabeledContent("Family", value: model.profile.modelFamily)
                if let cutoff = model.profile.knowledgeCutoff {
                    LabeledContent("Knowledge cutoff", value: cutoff.formatted)
                }
                if let window = model.contextWindowText {
                    LabeledContent("Context", value: window)
                }
                if let output = model.maxOutputText {
                    LabeledContent("Max output", value: output)
                }
            }
        }

        @ViewBuilder
        private var description: some View {
            if let detail = model.profile.description {
                Section("About") {
                    Text(detail)
                }
            }
        }

        @ViewBuilder
        private var strengths: some View {
            if let strengths = model.profile.strengths, !strengths.isEmpty {
                Section("Strengths") {
                    ForEach(strengths, id: \.self, content: Text.init)
                }
            }
        }

        @ViewBuilder
        private var bestFor: some View {
            if let bestFor = model.profile.bestFor, !bestFor.isEmpty {
                Section("Best for") {
                    ForEach(bestFor, id: \.self, content: Text.init)
                }
            }
        }

        @ViewBuilder
        private var pricing: some View {
            if let pricing = model.profile.pricing, !pricing.tiers.isEmpty {
                Section("Price per 1M tokens") {
                    ForEach(Array(pricing.tiers.enumerated()), id: \.offset) { _, tier in
                        LabeledContent(
                            tier.upToInputTokens.map { "Up to \($0)" } ?? "Above that",
                            value: String(
                                format: "in $%.2f / out $%.2f",
                                tier.inputPerMTok,
                                tier.outputPerMTok
                            )
                        )
                    }
                    if let cacheRead = pricing.cacheReadPerMTok {
                        LabeledContent("Cache read", value: String(format: "$%.2f", cacheRead))
                    }
                }
            }
        }
    }

#endif
