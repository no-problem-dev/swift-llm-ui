#if canImport(SwiftUI)

    import LLMClient
    import SwiftUI

    // MARK: - ModelDetailView

    /// One model in full: what it is, what it costs, and — when it is the one in use — how hard it
    /// should think.
    ///
    /// Choosing happens here rather than on the list, so the decision is made where the facts are
    /// rather than from a one-line summary.
    public struct ModelDetailView: View {
        private let model: ModelDescriptor
        private let providerName: String
        private let console: AgentConsole?

        @Environment(\.dismiss) private var dismiss

        /// - Parameters:
        ///   - model: The model to describe.
        ///   - providerName: How its provider is spelled.
        ///   - console: Lets this screen select the model and set its reasoning effort. Without
        ///     one the screen is read-only.
        public init(model: ModelDescriptor, providerName: String, console: AgentConsole? = nil) {
            self.model = model
            self.providerName = providerName
            self.console = console
        }

        private var isSelected: Bool {
            console?.selectedModelID == model.id
        }

        public var body: some View {
            List {
                if let console {
                    selection(console)
                }
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
        }

        @ViewBuilder
        private func selection(_ console: AgentConsole) -> some View {
            Section {
                Button {
                    console.selectedModelID = model.id
                } label: {
                    HStack {
                        Label(
                            isSelected ? "In use" : "Use this model",
                            systemImage: isSelected ? "checkmark.circle.fill" : "circle"
                        )
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .disabled(isSelected)
                .accessibilityIdentifier(AgentConsoleID.useModel)

                if isSelected {
                    Picker(
                        "Thinking",
                        selection: Binding(
                            get: { console.reasoningEffort },
                            set: { console.reasoningEffort = $0 }
                        )
                    ) {
                        Text("Model default").tag(ReasoningEffort?.none)
                        ForEach(ReasoningEffort.allCases, id: \.self) { effort in
                            Text(effort.rawValue.capitalized).tag(ReasoningEffort?.some(effort))
                        }
                    }
                    .accessibilityIdentifier(AgentConsoleID.effortPicker)
                }
            } footer: {
                if isSelected {
                    Text(
                        "Less thinking is faster and cheaper. A tier this model does not offer "
                            + "snaps to the nearest one it does."
                    )
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
                            tier.upToInputTokens.map { "Up to \($0.formatted())" } ?? "Above that",
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
                    if let reasoning = pricing.reasoningPerMTok {
                        LabeledContent("Reasoning", value: String(format: "$%.2f", reasoning))
                    }
                }
            }
        }
    }

#endif
