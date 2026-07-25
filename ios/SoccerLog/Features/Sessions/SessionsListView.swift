import SwiftUI

struct SessionsListView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var connectivity: Connectivity
    @Binding var openNewSession: Bool

    @State private var summaries: [SessionSummary] = []
    @State private var loading = false
    @State private var loadError: String?
    @State private var showNew = false

    private static let display: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f
    }()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.cream.ignoresSafeArea()
                content
            }
            .navigationTitle("Sessions")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNew = true } label: { Image(systemName: "plus.circle.fill") }
                        .accessibilityLabel("New session")
                }
                if !connectivity.isOnline {
                    ToolbarItem(placement: .topBarLeading) {
                        Pill(text: "Offline", color: Theme.warn)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button { showNew = true } label: {
                    Label("New session", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal).padding(.bottom, 8)
            }
            .sheet(isPresented: $showNew, onDismiss: reload) {
                NewSessionView()
            }
            .onChange(of: openNewSession) { _, v in if v { showNew = true; openNewSession = false } }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    @ViewBuilder private var content: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // Pending (unsynced) sessions captured offline.
                ForEach(store.queue.pending) { p in
                    PendingSessionRow(item: p)
                }
                if let loadError {
                    Card { Text(loadError).foregroundStyle(.red).font(.footnote) }
                }
                ForEach(summaries) { s in
                    NavigationLink(value: s) {
                        SessionRowView(summary: s, dateText: dateText(s))
                    }
                    .buttonStyle(.plain)
                }
                if summaries.isEmpty && store.queue.pending.isEmpty && !loading {
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No sessions yet").font(.headline).foregroundStyle(Theme.ink)
                            Text("Tap “New session” after Friday’s game.")
                                .font(.subheadline).foregroundStyle(Theme.inkSoft)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationDestination(for: SessionSummary.self) { s in
            SessionDetailView(sessionId: s.id)
        }
        .overlay { if loading && summaries.isEmpty { ProgressView() } }
    }

    private func dateText(_ s: SessionSummary) -> String {
        guard let d = s.playedDate else { return s.playedAt }
        return Self.display.string(from: d)
    }

    private func reload() { Task { await load() } }

    private func load() async {
        loading = true; loadError = nil
        do {
            await store.flushQueue()
            summaries = try await store.fetchSessionSummaries()
        } catch {
            loadError = "Couldn’t load sessions. \(error.localizedDescription)"
        }
        loading = false
    }
}

private struct SessionRowView: View {
    let summary: SessionSummary
    let dateText: String

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(dateText).font(.headline).foregroundStyle(Theme.ink)
                    if let loc = summary.location, !loc.isEmpty {
                        Text(loc).font(.subheadline).foregroundStyle(Theme.inkSoft)
                    }
                    Spacer()
                    if summary.isLowResponse { Pill(text: "Low response", color: Theme.warn) }
                }
                HStack(spacing: 20) {
                    Stat(value: "\(summary.headcount)", label: "players")
                    Stat(value: meanText, label: "mean")
                    Stat(value: rateText, label: "responded",
                         sample: "\(summary.responseCount)/\(summary.headcount)")
                }
            }
        }
    }

    private var meanText: String {
        guard let m = summary.meanOverall else { return "—" }
        return String(format: "%.1f", m)
    }
    private var rateText: String {
        guard let r = summary.responseRate else { return "—" }
        return "\(Int((r * 100).rounded()))%"
    }
}

private struct PendingSessionRow: View {
    let item: QueuedSession
    var body: some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.playedAt).font(.headline).foregroundStyle(Theme.ink)
                    Text("\(item.players.count) players").font(.subheadline).foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Pill(text: "Not synced", color: Theme.warn)
                }
            }
        }
    }
}
