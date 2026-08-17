#if canImport(SwiftUI)

    import LLMClient
    import SwiftUI

    // MARK: - Colour

    public extension TokenCategory {
        /// The colour this part is drawn in, everywhere it appears.
        var color: Color {
            switch self {
            case .cacheRead: .teal
            case .cacheWrite: .indigo
            case .input: .blue
            case .output: .orange
            case .reasoning: .purple
            }
        }
    }

    // MARK: - TokenBreakdownView

    /// A usage as two stacked bars: one by token count, one by cost.
    ///
    /// Shown together on purpose. Cached input is usually most of the tokens and almost none of
    /// the money, and only the pair of bars makes that visible — a count bar alone points at the
    /// wrong thing to optimise.
    public struct TokenBreakdownView: View {
        private let breakdown: TokenBreakdown
        private let settings: CostDisplaySettings?
        private let isCompact: Bool

        /// - Parameters:
        ///   - breakdown: What to draw.
        ///   - settings: Used to format the cost legend. Without it the cost bar is still drawn,
        ///     but unlabelled.
        ///   - isCompact: Thin bars and no legends, for a row inside a list.
        public init(
            _ breakdown: TokenBreakdown,
            settings: CostDisplaySettings? = nil,
            isCompact: Bool = false
        ) {
            self.breakdown = breakdown
            self.settings = settings
            self.isCompact = isCompact
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: isCompact ? 4 : 8) {
                bar(breakdown.tokenShares)

                if !isCompact {
                    legend(breakdown.slices) { "\($0.tokens.formatted())" }
                }

                let costShares = breakdown.costShares
                if !costShares.isEmpty {
                    bar(costShares)
                    if !isCompact {
                        legend(costShares.map(\.slice)) { slice in
                            slice.cost.map { settings?.format($0) ?? $0.formatted() } ?? ""
                        }
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityDescription)
        }

        private func bar(_ shares: [(slice: TokenBreakdown.Slice, share: Double)]) -> some View {
            GeometryReader { geometry in
                HStack(spacing: 1) {
                    ForEach(shares, id: \.slice.id) { entry in
                        Rectangle()
                            .fill(entry.slice.category.color)
                            // A slice worth a fraction of a percent still has to be visible, or a
                            // reader cannot tell "tiny" from "absent".
                            .frame(width: max(2, geometry.size.width * entry.share))
                    }
                }
            }
            .frame(height: isCompact ? 4 : 8)
            .clipShape(Capsule())
        }

        private func legend(
            _ slices: [TokenBreakdown.Slice],
            value: @escaping (TokenBreakdown.Slice) -> String
        ) -> some View {
            WrappingRow(spacing: 10, lineSpacing: 4) {
                ForEach(slices) { slice in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(slice.category.color)
                            .frame(width: 7, height: 7)
                        Text(slice.category.label)
                            .foregroundStyle(.secondary)
                        Text(value(slice))
                            .monospacedDigit()
                    }
                    .font(.caption2)
                }
            }
        }

        private var accessibilityDescription: String {
            let parts = breakdown.slices.map { "\($0.category.label) \($0.tokens)" }
            return ([ "\(breakdown.totalTokens) tokens" ] + parts).joined(separator: ", ")
        }
    }

    // MARK: - WrappingRow

    /// Lays subviews left to right, wrapping when the line is full.
    ///
    /// A legend has as many entries as the usage had parts, and the labels are of unequal width;
    /// an `HStack` would push the last one off the edge on a narrow screen.
    public struct WrappingRow: Layout {
        public var spacing: CGFloat = 8
        public var lineSpacing: CGFloat = 4

        public init(spacing: CGFloat = 8, lineSpacing: CGFloat = 4) {
            self.spacing = spacing
            self.lineSpacing = lineSpacing
        }

        public func sizeThatFits(
            proposal: ProposedViewSize,
            subviews: Subviews,
            cache _: inout ()
        ) -> CGSize {
            let maxWidth = proposal.width ?? .infinity
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0
            var widestLine: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if x > 0, x + size.width > maxWidth {
                    widestLine = max(widestLine, x - spacing)
                    y += lineHeight + lineSpacing
                    x = 0
                    lineHeight = 0
                }
                x += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }
            widestLine = max(widestLine, x - spacing)

            return CGSize(
                width: min(maxWidth, max(0, widestLine)),
                height: y + lineHeight
            )
        }

        public func placeSubviews(
            in bounds: CGRect,
            proposal _: ProposedViewSize,
            subviews: Subviews,
            cache _: inout ()
        ) {
            var x = bounds.minX
            var y = bounds.minY
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if x > bounds.minX, x + size.width > bounds.maxX {
                    y += lineHeight + lineSpacing
                    x = bounds.minX
                    lineHeight = 0
                }
                subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
                x += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }
        }
    }

#endif
