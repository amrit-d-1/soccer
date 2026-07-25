import SwiftUI
import Charts

@MainActor
final class InsightsModel: ObservableObject {
    @Published var headcount: [HeadcountBucket] = []
    @Published var presence: [PlayerPresence] = []
    @Published var disagreement: [DisagreementRow] = []
    @Published var trend: [TrendRow] = []
    @Published var loading = false
    @Published var error: String?

    func load(_ store: DataStore) async {
        loading = true; error = nil
        do {
            async let h = store.fetchHeadcountEffect()
            async let p = store.fetchPlayerPresence()
            async let d = store.fetchDisagreement()
            async let t = store.fetchTrend()
            headcount = try await h
            presence = try await p
            disagreement = try await d
            trend = try await t
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    var presenceQualified: [PlayerPresence] {
        presence.filter { $0.hasEnoughData }
            .sorted { ($0.appearances) > ($1.appearances) }
    }
    var presenceInsufficient: [PlayerPresence] {
        presence.filter { !$0.hasEnoughData }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
}

struct InsightsView: View {
    @EnvironmentObject var store: DataStore
    @StateObject private var model = InsightsModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.cream.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        if let e = model.error {
                            Card { Text(e).font(.footnote).foregroundStyle(.red) }
                        }
                        Card {
                            Text("Sessions below 40% response are excluded from every chart here and flagged in the Sessions list.")
                                .font(.footnote).foregroundStyle(Theme.inkSoft)
                        }
                        headcountCard
                        presenceCard
                        disagreementCard
                        trendCard
                    }
                    .padding()
                }
                .overlay { if model.loading && model.headcount.isEmpty { ProgressView() } }
            }
            .navigationTitle("Insights")
            .task { await model.load(store) }
            .refreshable { await model.load(store) }
        }
    }

    // 1. Headcount effect — put first; likely the strongest signal.
    private var headcountCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Headcount effect").font(.headline).foregroundStyle(Theme.ink)
                Text("Mean rating by number of players").font(.caption).foregroundStyle(Theme.inkSoft)
                if model.headcount.isEmpty {
                    emptyNote
                } else {
                    Chart(model.headcount) { b in
                        BarMark(
                            x: .value("Players", b.bucket),
                            y: .value("Mean", b.meanRating ?? 0)
                        )
                        .foregroundStyle(Theme.amber)
                        .annotation(position: .top) {
                            Text(b.meanRating.map { String(format: "%.1f", $0) } ?? "—")
                                .font(Theme.mono(11)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                    .chartYScale(domain: 0.0...5.0)
                    .frame(height: 170)
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(model.headcount) { b in
                            Text("\(b.bucket): \(b.sessionCount) sessions, \(b.nRatings) ratings")
                                .font(Theme.mono(11)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                }
            }
        }
    }

    // 2. Player presence delta — neutral framing, shrinkage-adjusted.
    private var presenceCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Player presence").font(.headline).foregroundStyle(Theme.ink)
                Text("Mean session rating in games with vs. without each player. Adjusted toward the global mean (k = 5) so small samples don’t dominate.")
                    .font(.caption).foregroundStyle(Theme.inkSoft)

                if model.presenceQualified.isEmpty && model.presenceInsufficient.isEmpty {
                    emptyNote
                }
                ForEach(model.presenceQualified) { p in
                    PresenceRow(p: p)
                    if p.id != model.presenceQualified.last?.id { Divider() }
                }
                if !model.presenceInsufficient.isEmpty {
                    Divider()
                    Text("Not enough data yet (under 6 appearances)")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.inkSoft)
                    ForEach(model.presenceInsufficient) { p in
                        HStack {
                            Text(p.name).foregroundStyle(Theme.inkSoft)
                            Spacer()
                            Text("\(p.appearances) games").font(Theme.mono(12)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                }
            }
        }
    }

    // 3. Disagreement — session std dev vs mean balance.
    private var disagreementCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Disagreement").font(.headline).foregroundStyle(Theme.ink)
                Text("Spread of ratings within a session vs. how even the teams felt. High spread often means lopsided sides.")
                    .font(.caption).foregroundStyle(Theme.inkSoft)
                let pts = model.disagreement.filter { $0.stddevOverall != nil && $0.meanBalance != nil }
                if pts.isEmpty {
                    emptyNote
                } else {
                    Chart(pts) { r in
                        PointMark(
                            x: .value("Mean balance", r.meanBalance ?? 0),
                            y: .value("Std dev", r.stddevOverall ?? 0)
                        )
                        .foregroundStyle(Theme.amber)
                    }
                    .chartXScale(domain: 1.0...5.0)
                    .chartXAxisLabel("mean balance (1–5)")
                    .chartYAxisLabel("std dev of overall")
                    .frame(height: 170)
                    Text("\(pts.count) sessions plotted").font(Theme.mono(11)).foregroundStyle(Theme.inkSoft)
                }
            }
        }
    }

    // 4. Trend — mean rating over time with 4-game rolling average.
    private var trendCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Trend").font(.headline).foregroundStyle(Theme.ink)
                Text("Mean rating per session with a 4-game rolling average").font(.caption).foregroundStyle(Theme.inkSoft)
                let pts = model.trend.filter { $0.playedDate != nil }
                if pts.isEmpty {
                    emptyNote
                } else {
                    Chart {
                        ForEach(pts) { r in
                            LineMark(x: .value("Date", r.playedDate!), y: .value("Mean", r.meanOverall ?? 0),
                                     series: .value("s", "Mean"))
                                .foregroundStyle(Theme.inkSoft.opacity(0.5))
                            PointMark(x: .value("Date", r.playedDate!), y: .value("Mean", r.meanOverall ?? 0))
                                .foregroundStyle(Theme.inkSoft.opacity(0.5))
                        }
                        ForEach(pts) { r in
                            LineMark(x: .value("Date", r.playedDate!), y: .value("Rolling", r.rollingAvg4 ?? 0),
                                     series: .value("s", "4-game avg"))
                                .foregroundStyle(Theme.amber)
                                .lineStyle(.init(lineWidth: 2.5))
                        }
                    }
                    .chartYScale(domain: 0.0...5.0)
                    .frame(height: 180)
                    Text("\(pts.count) qualifying sessions").font(Theme.mono(11)).foregroundStyle(Theme.inkSoft)
                }
            }
        }
    }

    private var emptyNote: some View {
        Text("Not enough qualifying sessions yet.").font(.subheadline).foregroundStyle(Theme.inkSoft)
    }
}

private struct PresenceRow: View {
    let p: PlayerPresence
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(p.name).foregroundStyle(Theme.ink)
                Spacer()
                Text("\(p.appearances) games").font(Theme.mono(12)).foregroundStyle(Theme.inkSoft)
            }
            HStack(spacing: 16) {
                labelled("with", p.meanWith, n: p.nWith)
                labelled("without", p.meanWithout, n: p.nWithout)
                labelled("adj.", p.adjustedWith, n: nil, emphasize: true)
            }
        }
        .padding(.vertical, 2)
    }

    private func labelled(_ title: String, _ value: Double?, n: Int?, emphasize: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value.map { String(format: "%.2f", $0) } ?? "—")
                .font(Theme.mono(14, weight: emphasize ? .semibold : .regular))
                .foregroundStyle(emphasize ? Theme.amber : Theme.ink)
            Text(n != nil ? "\(title) (n=\(n!))" : title)
                .font(.caption2).foregroundStyle(Theme.inkSoft)
        }
    }
}
