#if canImport(SwiftUI)

    import SwiftUI

    // MARK: - InspectablePayload

    /// A structured blob worth reading in full — a rendered UI description, a tool's arguments,
    /// a request body.
    ///
    /// The package cannot know what any of these mean, so it does not try: a host names them and
    /// hands over the text, and this draws them so nobody writes another JSON viewer.
    public struct InspectablePayload: Identifiable, Sendable, Hashable {
        public let id: String

        /// What this payload is. Shown as the row's title.
        public let title: String

        /// A word about where it came from — a surface id, a tool name, a step number.
        public let subtitle: String?

        /// The body, already formatted the way it should be read.
        public let text: String

        public init(id: String, title: String, subtitle: String? = nil, text: String) {
            self.id = id
            self.title = title
            self.subtitle = subtitle
            self.text = text
        }
    }

    // MARK: - PayloadInspectorView

    /// Lists payloads, each opening onto its full text.
    ///
    /// Long structured text is unreadable inline and indispensable when something renders wrong,
    /// so the list stays scannable and the body is one tap away.
    public struct PayloadInspectorView: View {
        private let payloads: [InspectablePayload]
        private let emptyMessage: String
        private let onCopy: ((String) -> Void)?

        @State private var selected: InspectablePayload?

        public init(
            payloads: [InspectablePayload],
            emptyMessage: String,
            onCopy: ((String) -> Void)? = nil
        ) {
            self.payloads = payloads
            self.emptyMessage = emptyMessage
            self.onCopy = onCopy
        }

        public var body: some View {
            Group {
                if payloads.isEmpty {
                    DebugEmptyHint(emptyMessage)
                } else {
                    List(payloads) { payload in
                        row(payload)
                            .contentShape(Rectangle())
                            .onTapGesture { selected = payload }
                    }
                    .listStyle(.plain)
                }
            }
            .toolbar {
                if let onCopy, !payloads.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        CopyButton(
                            text: { payloads.map(\.text).joined(separator: "\n\n") },
                            onCopy: onCopy
                        )
                    }
                }
            }
            .sheet(item: $selected) { payload in
                detail(payload)
            }
        }

        private func row(_ payload: InspectablePayload) -> some View {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(payload.title)
                        .font(.subheadline.weight(.semibold))
                    if let subtitle = payload.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Text("\(payload.text.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(payload.text)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.vertical, 2)
        }

        private func detail(_ payload: InspectablePayload) -> some View {
            NavigationStack {
                ScrollView {
                    Text(payload.text)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
                .navigationTitle(payload.title)
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
                    .toolbar {
                        if let onCopy {
                            ToolbarItem(placement: .primaryAction) {
                                CopyButton(text: { payload.text }, onCopy: onCopy)
                            }
                        }
                    }
            }
        }
    }

#endif
