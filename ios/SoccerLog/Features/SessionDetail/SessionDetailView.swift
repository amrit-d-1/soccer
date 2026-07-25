import SwiftUI
import Charts

/// One bar of the 1–5 distribution.
struct ScoreCount: Identifiable, Hashable {
    let score: Int
    let count: Int
    var id: Int { score }
}

@MainActor
final class SessionDetailModel: ObservableObject {
    @Published var summary: SessionSummary?
    @Published var roster: [Player] = []
    @Published var ratings: [Rating] = []
    @Published var links: [LinkWithPlayer] = []
    @Published var loading = false
    @Published var banner: String?

    func load(_ store: DataStore, id: UUID) async {
        loading = true
        async let s = try? await store.fetchSessionSummary(id: id)
        async let r = try? await store.fetchAppearances(sessionId: id)
        async let rt = try? await store.fetchRatings(sessionId: id)
        async let lk = try? await store.fetchLinksWithPlayers(sessionId: id)
        summary = await s ?? summary
        roster = await r ?? []
        ratings = await rt ?? []
        links = await lk ?? []
        loading = false
    }

    /// 1...5 -> count, for the bar chart.
    var distribution: [ScoreCount] {
        (1...5).map { score in ScoreCount(score: score, count: ratings.filter { $0.overall == score }.count) }
    }

    var comments: [Rating] { ratings.filter { !($0.comment ?? "").isEmpty } }

    var nonResponders: [LinkWithPlayer] { links.filter { !$0.hasResponded } }
}

struct SessionDetailView: View {
    @EnvironmentObject var store: DataStore
    let sessionId: UUID
    @StateObject private var model = SessionDetailModel()

    @State private var sending = false
    @AppStorage private var reminderSent: Bool

    init(sessionId: UUID) {
        self.sessionId = sessionId
        _reminderSent = AppStorage(wrappedValue: false, "reminderSent-\(sessionId.uuidString)")
    }

    private static let display: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"; return f
    }()

    var body: some View {
        ZStack {
            Theme.cream.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    if let b = model.banner {
                        Card { Text(b).font(.footnote).foregroundStyle(Theme.good) }
                    }
                    statsCard
                    distributionCard
                    actionsCard
                    nonResponderCard
                    commentsCard
                }
                .padding()
            }
            .overlay { if model.loading && model.summary == nil { ProgressView() } }
        }
        .navigationTitle(titleText)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load(store, id: sessionId) }
        .refreshable { await model.load(store, id: sessionId) }
    }

    private var titleText: String {
        guard let d = model.summary?.playedDate else { return "Session" }
        return Self.display.string(from: d)
    }

    private var statsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                if let loc = model.summary?.location, !loc.isEmpty {
                    Text(loc).font(.subheadline).foregroundStyle(Theme.inkSoft)
                }
                HStack(spacing: 22) {
                    Stat(value: "\(model.summary?.headcount ?? model.roster.count)", label: "players")
                    Stat(value: meanText, label: "mean overall")
                    Stat(value: sdText, label: "std dev")
                }
                HStack(spacing: 22) {
                    Stat(value: rateText, label: "responded",
                         sample: "\(model.summary?.responseCount ?? model.ratings.count)/\(model.summary?.headcount ?? model.roster.count)")
                    Stat(value: balanceText, label: "mean balance")
                }
                if model.summary?.isLowResponse == true {
                    Pill(text: "Below 40% — excluded from insights", color: Theme.warn)
                }
            }
        }
    }

    private var distributionCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Rating distribution").font(.headline).foregroundStyle(Theme.ink)
                if model.ratings.isEmpty {
                    Text("No ratings yet.").font(.subheadline).foregroundStyle(Theme.inkSoft)
                } else {
                    Chart(model.distribution) { item in
                        BarMark(
                            x: .value("Score", "\(item.score)"),
                            y: .value("Count", item.count)
                        )
                        .foregroundStyle(Theme.amber)
                        .annotation(position: .top) {
                            if item.count > 0 {
                                Text("\(item.count)").font(Theme.mono(11)).foregroundStyle(Theme.inkSoft)
                            }
                        }
                    }
                    .chartYAxis { AxisMarks(position: .leading) }
                    .frame(height: 160)
                }
            }
        }
    }

    private var actionsCard: some View {
        Card {
            VStack(spacing: 10) {
                Button {
                    send(mode: "initial")
                } label: { Label("Send rating requests", systemImage: "paperplane.fill") }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(sending)

                Button {
                    send(mode: "reminder")
                    reminderSent = true
                } label: {
                    Label(reminderSent ? "Reminder sent" : "Send reminder (non-responders)",
                          systemImage: "bell")
                }
                .disabled(sending || reminderSent || model.nonResponders.isEmpty)
                .foregroundStyle(reminderSent ? Theme.inkSoft : Theme.amber)

                Button {
                    copyLinks()
                } label: { Label("Copy links", systemImage: "doc.on.doc") }
                    .foregroundStyle(Theme.amber)

                if sending { ProgressView() }
            }
        }
    }

    @ViewBuilder private var nonResponderCard: some View {
        if !model.nonResponders.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hasn’t responded (\(model.nonResponders.count))")
                        .font(.headline).foregroundStyle(Theme.ink)
                    ForEach(model.nonResponders) { l in
                        HStack {
                            Text(l.name).foregroundStyle(Theme.ink)
                            if l.phone == nil { Pill(text: "no phone", color: Theme.inkSoft) }
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var commentsCard: some View {
        if !model.comments.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Comments (\(model.comments.count))").font(.headline).foregroundStyle(Theme.ink)
                    ForEach(model.comments) { r in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.comment ?? "").foregroundStyle(Theme.ink)
                            Text("rated \(r.overall)/5").font(Theme.mono(11)).foregroundStyle(Theme.inkSoft)
                        }
                        if r.id != model.comments.last?.id { Divider() }
                    }
                }
            }
        }
    }

    // MARK: derived text

    private var meanText: String { model.summary?.meanOverall.map { String(format: "%.1f", $0) } ?? "—" }
    private var sdText: String { model.summary?.stddevOverall.map { String(format: "%.2f", $0) } ?? "—" }
    private var balanceText: String { model.summary?.meanBalance.map { String(format: "%.1f", $0) } ?? "—" }
    private var rateText: String {
        guard let r = model.summary?.responseRate else { return "—" }
        return "\(Int((r * 100).rounded()))%"
    }

    // MARK: actions

    private func send(mode: String) {
        sending = true; model.banner = nil
        Task {
            do {
                let res = try await store.sendRatingRequests(sessionId: sessionId, mode: mode)
                model.banner = "Sent \(res.sent) · skipped \(res.skipped) · failed \(res.failed) (provider logs in Supabase)."
                await model.load(store, id: sessionId)
            } catch {
                model.banner = "Send failed: \(error.localizedDescription). Use Copy links as a fallback."
            }
            sending = false
        }
    }

    private func copyLinks() {
        let lines = model.links.map { "\($0.name): \(AppConfig.ratingLink(token: $0.token))" }
        UIPasteboard.general.string = lines.joined(separator: "\n")
        model.banner = "Copied \(lines.count) links to the clipboard."
    }
}
