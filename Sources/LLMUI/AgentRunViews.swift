#if canImport(SwiftUI)

    import SwiftUI

    // MARK: - AgentRunListView

    /// Every run in the session, newest first.
    ///
    /// The list is of runs rather than entries because a run is what a person remembers doing —
    /// "the one I just sent" — and a flat list of a few hundred entries has no such handle in it.
    public struct AgentRunListView: View {
        private let log: AgentTraceLog
        private let emptyMessage: String
        private let onCopy: ((String) -> Void)?

        public init(log: AgentTraceLog, emptyMessage: String, onCopy: ((String) -> Void)? = nil) {
            self.log = log
            self.emptyMessage = emptyMessage
            self.onCopy = onCopy
        }

        private var runs: [AgentTraceLog.Run] {
            log.runs.reversed()
        }

        public var body: some View {
            Group {
                if runs.isEmpty {
                    ContentUnavailableView(
                        "Nothing recorded",
                        systemImage: "list.bullet.rectangle",
                        description: Text(emptyMessage)
                    )
                } else {
                    List {
                        Section {
                            ForEach(runs) { run in
                                NavigationLink {
                                    AgentRunView(run: run, log: log, onCopy: onCopy)
                                } label: {
                                    AgentRunRow(run: run)
                                }
                                .accessibilityIdentifier(AgentConsoleID.run(run.id))
                            }
                        } footer: {
                            Text("Every entry belongs to the run it happened in.")
                        }
                    }
                }
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
        }
    }

    // MARK: - AgentRunRow

    /// A run as it appears in a list: when, what it was, how it went.
    struct AgentRunRow: View {
        let run: AgentTraceLog.Run

        var body: some View {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: run.hasFailure ? "exclamationmark.triangle.fill" : "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(run.hasFailure ? Color.red : Color.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if let at = run.at {
                            Text(at, format: .dateTime.hour().minute().second())
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        if let duration = run.duration {
                            Text(String(format: "%.1fs", duration))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Text(run.label ?? "Run \(run.index)")
                        .font(.callout)
                        .lineLimit(2)

                    Text(tally)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
        }

        /// What the run consisted of, counting only the kinds that actually occurred.
        private var tally: String {
            let parts = AgentTraceLog.Kind.allCases.compactMap { kind -> String? in
                let count = run.count(of: kind)
                return count > 0 ? "\(kind.label.lowercased()) \(count)" : nil
            }
            return parts.isEmpty ? "empty" : parts.joined(separator: " · ")
        }
    }

    // MARK: - AgentRunView

    /// One run in full: everything recorded during it, oldest first.
    ///
    /// Oldest first here, unlike the run list. Within a run the question is how it unfolded, and
    /// causes read better before their effects.
    public struct AgentRunView: View {
        private let run: AgentTraceLog.Run
        private let log: AgentTraceLog
        private let onCopy: ((String) -> Void)?

        @State private var filter: AgentTraceLog.Kind?

        public init(run: AgentTraceLog.Run, log: AgentTraceLog, onCopy: ((String) -> Void)? = nil) {
            self.run = run
            self.log = log
            self.onCopy = onCopy
        }

        private var filtered: [AgentTraceLog.Entry] {
            guard let filter else {
                return run.entries
            }
            return run.entries.filter { $0.kind == filter }
        }

        public var body: some View {
            VStack(spacing: 0) {
                FilterChips(
                    options: [(nil, "All", run.entries.count)]
                        + AgentTraceLog.Kind.allCases.compactMap { kind in
                            let count = run.count(of: kind)
                            return count > 0 ? (kind, kind.label, count) : nil
                        },
                    selection: $filter
                )
                Divider()
                list
            }
            .navigationTitle(run.label ?? "Run \(run.index)")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    if let onCopy {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                onCopy(log.transcript(of: run))
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .accessibilityLabel(Text("Copy run"))
                        }
                    }
                }
        }

        @ViewBuilder
        private var list: some View {
            if filtered.isEmpty {
                ContentUnavailableView(
                    "Nothing of that kind",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("This run recorded no \(filter?.label.lowercased() ?? "") entries.")
                )
            } else {
                List(filtered) { entry in
                    NavigationLink {
                        AgentEntryView(entry: entry, onCopy: onCopy)
                    } label: {
                        AgentEntryRow(entry: entry)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - AgentEntryRow

    /// One entry as it appears in a run: kind, time, and as much of it as fits.
    struct AgentEntryRow: View {
        let entry: AgentTraceLog.Entry

        var body: some View {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: entry.kind.systemImage)
                        .font(.caption2)
                        .foregroundStyle(entry.kind.tintName.color)
                    Text(entry.kind.label)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(entry.kind.tintName.color.opacity(0.18)))
                        .foregroundStyle(entry.kind.tintName.color)
                    Text(entry.at, format: .dateTime.hour().minute().second())
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if entry.result != nil {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Text(AgentTraceLog.markingEdgeWhitespace(entry.summary))
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

    // MARK: - AgentEntryView

    /// One entry in full, with its result beside it when it has one.
    public struct AgentEntryView: View {
        private let entry: AgentTraceLog.Entry
        private let onCopy: ((String) -> Void)?

        public init(entry: AgentTraceLog.Entry, onCopy: ((String) -> Void)? = nil) {
            self.entry = entry
            self.onCopy = onCopy
        }

        public var body: some View {
            List {
                Section {
                    Text(AgentTraceLog.markingEdgeWhitespace(entry.summary))
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                    LabeledContent(
                        "At",
                        value: entry.at.formatted(date: .omitted, time: .standard)
                    )
                }

                if entry.deltas.count > 1 {
                    Section {
                        ForEach(Array(entry.deltas.enumerated()), id: \.offset) { index, delta in
                            LabeledContent("\(index + 1)") {
                                Text(AgentTraceLog.markingEdgeWhitespace(delta))
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                            }
                        }
                    } header: {
                        Text("Deltas (\(entry.deltas.count))")
                    } footer: {
                        Text("How the pieces arrived. ␊ is a newline, ␠ a space, at either end.")
                    }
                }

                if let detail = entry.detail, !detail.isEmpty {
                    Section {
                        Text(detail)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    } header: {
                        Text(entry.result == nil ? "Detail" : "Sent")
                    }
                }

                if let result = entry.result, !result.isEmpty {
                    Section {
                        Text(result)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    } header: {
                        Text("Returned")
                    }
                }
            }
            .navigationTitle(entry.kind.label)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    if let onCopy {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Copy") {
                                onCopy(AgentTraceLog.describing(entry))
                            }
                        }
                    }
                }
        }
    }

#endif
