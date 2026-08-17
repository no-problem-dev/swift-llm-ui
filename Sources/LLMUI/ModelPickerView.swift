#if canImport(SwiftUI)

    import LLMClient
    import LLMCloudBranding
    import SwiftUI

    // MARK: - ModelPickerView

    /// Lets someone pick a model out of a `ModelCatalog`.
    ///
    /// The view reads descriptors and nothing else, so it never names a provider. Offering one
    /// more provider means adding its `descriptors` to the catalog; this file does not change.
    public struct ModelPickerView: View {
        private let catalog: ModelCatalog
        private let providerNames: [String: String]
        @Binding private var selectedModelID: String

        @State private var detail: ModelDescriptor?

        /// - Parameters:
        ///   - catalog: The models on offer.
        ///   - selectedModelID: The chosen model's `ModelDescriptor.id`. Written on selection.
        ///   - providerNames: How to spell each `providerID` in a section header. A provider left
        ///     out is headed by its identifier, which is legible enough to ship without.
        public init(
            catalog: ModelCatalog,
            selectedModelID: Binding<String>,
            providerNames: [String: String] = [:]
        ) {
            self.catalog = catalog
            _selectedModelID = selectedModelID
            self.providerNames = providerNames
        }

        public var body: some View {
            List {
                ForEach(catalog.providerIDs, id: \.self) { providerID in
                    Section {
                        ForEach(catalog.models(providerID: providerID)) { model in
                            row(model)
                        }
                    } header: {
                        header(providerID)
                    }
                }
            }
            .sheet(item: $detail) { model in
                ModelDetailView(
                    model: model,
                    providerName: providerNames[model.providerID] ?? model.providerID
                )
            }
        }

        private func header(_ providerID: String) -> some View {
            HStack(spacing: 6) {
                if let brand = CloudProviderBrand(rawValue: providerID) {
                    CloudProviderLogo(brand, size: 14)
                }
                Text(providerNames[providerID] ?? providerID)
            }
        }

        private func row(_ model: ModelDescriptor) -> some View {
            let isSelected = model.id == selectedModelID
            return Button {
                selectedModelID = model.id
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.displayName)
                            .font(.body)
                            .foregroundStyle(.primary)
                        Text(model.profile.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)

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

                        Text(model.modelID)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                    }

                    Spacer(minLength: 0)

                    Button {
                        detail = model
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("Details"))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

#endif
