#if canImport(SwiftUI)

    import SwiftUI

    // MARK: - DebugCard

    /// A titled block of debug facts.
    ///
    /// Cards rather than `Form` sections because these screens mix prose, numbers and charts, and
    /// a grouped list flattens all three into rows of the same weight.
    public struct DebugCard<Content: View>: View {
        private let title: String
        private let systemImage: String
        private let isAlarming: Bool
        private let content: Content

        /// - Parameter isAlarming: Draws the title in red. For a card that only appears when
        ///   something went wrong.
        public init(
            _ title: String,
            systemImage: String,
            isAlarming: Bool = false,
            @ViewBuilder content: () -> Content
        ) {
            self.title = title
            self.systemImage = systemImage
            self.isAlarming = isAlarming
            self.content = content()
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isAlarming ? Color.red : Color.primary)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.debugCardBackground)
            )
        }
    }

    // MARK: - DebugRow

    /// A label on the left, a value on the right.
    public struct DebugRow: View {
        private let key: String
        private let value: String
        private let accent: Color?

        public init(_ key: String, _ value: String, accent: Color? = nil) {
            self.key = key
            self.value = value
            self.accent = accent
        }

        public var body: some View {
            HStack(alignment: .top) {
                Text(key)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(value)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(accent ?? .primary)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - DebugMetric

    /// A number with its name underneath, for a row of headline figures.
    public struct DebugMetric: View {
        private let label: String
        private let value: String
        private let tint: Color?

        public init(_ label: String, _ value: String, tint: Color? = nil) {
            self.label = label
            self.value = value
            self.tint = tint
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(tint ?? .primary)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - CopyButton

    /// Copies text, and says so for a moment.
    ///
    /// Owns its own confirmation so callers do not each re-implement the flash; the copy itself is
    /// a closure because the pasteboard type differs per platform.
    public struct CopyButton: View {
        private let text: () -> String
        private let onCopy: (String) -> Void

        @State private var hasCopied = false

        public init(text: @escaping () -> String, onCopy: @escaping (String) -> Void) {
            self.text = text
            self.onCopy = onCopy
        }

        public var body: some View {
            Button {
                onCopy(text())
                hasCopied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.2))
                    hasCopied = false
                }
            } label: {
                Image(systemName: hasCopied ? "checkmark" : "doc.on.doc")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text(hasCopied ? "Copied" : "Copy"))
        }
    }

    // MARK: - DebugEmptyHint

    /// Says why a screen is empty and what would fill it.
    public struct DebugEmptyHint: View {
        private let text: String

        public init(_ text: String) {
            self.text = text
        }

        public var body: some View {
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        }
    }

    // MARK: - FilterChips

    /// A scrolling row of filters, each with how many items it would show.
    ///
    /// The counts are the point: they say where the interesting entries are before anything is
    /// tapped, and a filter that would show nothing can be left out by the caller.
    public struct FilterChips<Value: Hashable>: View {
        private let options: [(value: Value?, label: String, count: Int)]
        @Binding private var selection: Value?

        public init(
            options: [(value: Value?, label: String, count: Int)],
            selection: Binding<Value?>
        ) {
            self.options = options
            _selection = selection
        }

        public var body: some View {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                        chip(option)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
        }

        private func chip(_ option: (value: Value?, label: String, count: Int)) -> some View {
            let isSelected = selection == option.value
            return Button {
                selection = option.value
            } label: {
                HStack(spacing: 4) {
                    Text(option.label)
                        .font(.caption.weight(.semibold))
                    if option.count > 0 {
                        Text("\(option.count)")
                            .font(.caption2.monospacedDigit())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(
                                    isSelected ? Color.accentColor : Color.secondary.opacity(0.2)
                                )
                            )
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(
                        isSelected
                            ? Color.accentColor.opacity(0.18)
                            : Color.debugCardBackground
                    )
                )
                .overlay(
                    Capsule().stroke(isSelected ? Color.accentColor : .clear, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Palette

    extension Color {
        /// The fill behind a debug card, one step off the screen's own background.
        static var debugCardBackground: Color {
            #if canImport(UIKit)
                Color(uiColor: .secondarySystemBackground)
            #elseif canImport(AppKit)
                Color(nsColor: .controlBackgroundColor)
            #else
                Color.gray.opacity(0.12)
            #endif
        }
    }

#endif
