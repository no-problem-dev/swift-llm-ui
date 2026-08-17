#if canImport(SwiftUI)

    import SwiftUI

    public extension AgentTraceLog.TintName {
        /// The colour this tint means.
        var color: Color {
            switch self {
            case .neutral: .secondary
            case .warm: .orange
            case .cool: .blue
            case .alarming: .red
            case .spending: .purple
            }
        }
    }

    // MARK: - AgentTraceView

    /// Shows what an ``AgentTraceLog`` collected, as the runs that produced it.
    ///
    /// Runs newest first, because the reason for opening this is almost always the thing that just
    /// happened. Opening one shows what it did, in order.
    public struct AgentTraceView: View {
        private let log: AgentTraceLog
        private let emptyMessage: String
        private let onCopy: ((String) -> Void)?

        /// - Parameters:
        ///   - log: What to show.
        ///   - emptyMessage: Shown when nothing has been recorded. Say what would fill it.
        ///   - onCopy: Called with text to put on the pasteboard. `nil` hides the copy buttons —
        ///     the pasteboard type differs per platform, so the caller supplies the write.
        public init(
            log: AgentTraceLog,
            emptyMessage: String,
            onCopy: ((String) -> Void)? = nil
        ) {
            self.log = log
            self.emptyMessage = emptyMessage
            self.onCopy = onCopy
        }

        public var body: some View {
            AgentRunListView(log: log, emptyMessage: emptyMessage, onCopy: onCopy)
        }
    }

#endif
