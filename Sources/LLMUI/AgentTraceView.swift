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

    /// Shows what an ``AgentTraceLog`` collected: newest first, filterable, with the long form
    /// behind a tap.
    ///
    /// Entries are listed newest first because the reason for opening this is almost always the
    /// thing that just happened.
    public struct AgentTraceView: View {
        private let log: AgentTraceLog
        private let emptyMessage: String
        private let onCopy: ((String) -> Void)?

        @State private var filter: AgentTraceLog.Kind?
        @State private var selected: AgentTraceLog.Entry?

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

        private var filtered: [AgentTraceLog.Entry] {
            let newestFirst = log.entries.reversed()
            guard let filter else {
                return Array(newestFirst)
            }
            return newestFirst.filter { $0.kind == filter }
        }

        public var body: some View {
            VStack(spacing: 0) {
                chips
                Divider()
                content
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Clear") { log.clear() }
                        .disabled(log.entries.isEmpty)
                }
                if let onCopy {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            onCopy(log.transcript())
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .disabled(log.entries.isEmpty)
                        .accessibilityLabel(Text("Copy all"))
                    }
                }
            }
            .sheet(item: $selected) { entry in
                detail(entry)
            }
        }

        @ViewBuilder
        private var content: some View {
            if filtered.isEmpty {
                ContentUnavailableView(
                    "Nothing recorded",
                    systemImage: "list.bullet.rectangle",
                    description: Text(emptyMessage)
                )
            } else {
                List(filtered) { entry in
                    row(entry)
                        .contentShape(Rectangle())
                        .onTapGesture { selected = entry }
                }
                .listStyle(.plain)
            }
        }

        private var chips: some View {
            FilterChips(
                options: [(nil, "All", log.entries.count)]
                    + AgentTraceLog.Kind.allCases.compactMap { kind in
                        let count = log.entries.count { $0.kind == kind }
                        return count > 0 ? (kind, kind.label, count) : nil
                    },
                selection: $filter
            )
        }

        private func row(_ entry: AgentTraceLog.Entry) -> some View {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: entry.kind.systemImage)
                    .font(.caption)
                    .foregroundStyle(entry.kind.tintName.color)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(entry.kind.label)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(entry.kind.tintName.color.opacity(0.18))
                            )
                            .foregroundStyle(entry.kind.tintName.color)
                        Text(entry.at, format: .dateTime.hour().minute().second())
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Text(entry.summary)
                        .font(.caption.monospaced())
                        .foregroundStyle(entry.kind == .failure ? Color.red : Color.primary)
                        .lineLimit(3)

                    if let detail = entry.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }

        private func detail(_ entry: AgentTraceLog.Entry) -> some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(entry.summary)
                            .font(.callout.monospaced())
                        if let detail = entry.detail, !detail.isEmpty {
                            Divider()
                            Text(detail)
                                .font(.caption.monospaced())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding()
                }
                .navigationTitle(entry.kind.rawValue)
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
                    .toolbar {
                        if let onCopy {
                            ToolbarItem(placement: .primaryAction) {
                                Button("Copy") {
                                    onCopy(
                                        [entry.summary, entry.detail]
                                            .compactMap(\.self)
                                            .joined(separator: "\n")
                                    )
                                }
                            }
                        }
                    }
            }
        }
    }

#endif
