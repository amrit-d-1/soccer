import SwiftUI

/// A pickable player — either an existing roster member or a brand-new one
/// added inline during this session.
struct PickPlayer: Identifiable, Hashable {
    let id: UUID
    var name: String
    var phone: String?
    var existingId: UUID?     // nil => created inline, resolved on save
    var smsOptOut: Bool

    var hasPhone: Bool { !(phone ?? "").isEmpty }
}

@MainActor
final class NewSessionModel: ObservableObject {
    @Published var playedAt = Date()
    @Published var location = ""
    @Published var notes = ""
    @Published var search = ""

    @Published var roster: [PickPlayer] = []       // existing, recency-ordered
    @Published var added: [PickPlayer] = []        // inline-added this session
    @Published var selected: [UUID] = []           // selection order preserved
    @Published var loading = false

    private var byId: [UUID: PickPlayer] = [:]

    var selectedCount: Int { selected.count }

    func rebuildIndex() {
        byId = Dictionary(uniqueKeysWithValues: (roster + added).map { ($0.id, $0) })
    }

    func load(_ store: DataStore) async {
        loading = true
        if let players = try? await store.fetchPlayersByRecency() {
            roster = players.map {
                PickPlayer(id: $0.id, name: $0.name, phone: $0.phone,
                           existingId: $0.id, smsOptOut: $0.smsOptOut)
            }
        }
        rebuildIndex()
        loading = false
    }

    /// Players matching the search, excluding already-selected (those pin to top).
    var filtered: [PickPlayer] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let pool = (added + roster)
        let notSelected = pool.filter { !selected.contains($0.id) }
        guard !q.isEmpty else { return notSelected }
        return notSelected.filter { $0.name.lowercased().contains(q) }
    }

    var selectedPlayers: [PickPlayer] { selected.compactMap { byId[$0] } }

    /// Whether the exact typed name already exists, to decide showing "Add".
    var canAddTyped: Bool {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return false }
        return !(roster + added).contains { $0.name.lowercased() == q.lowercased() }
    }

    func toggle(_ id: UUID) {
        if let idx = selected.firstIndex(of: id) { selected.remove(at: idx) }
        else { selected.append(id) }
    }

    func addInline(name: String, phone: String?) {
        let p = PickPlayer(id: UUID(), name: name, phone: Phone.normalize(phone),
                           existingId: nil, smsOptOut: false)
        added.insert(p, at: 0)
        selected.append(p.id)
        rebuildIndex()
        search = ""
    }

    func makeQueued() -> QueuedSession {
        let fmt = DateParse.dayFormatter
        let players = selectedPlayers.map {
            QueuedPlayer(existingId: $0.existingId, name: $0.name,
                         phone: $0.phone, contactId: nil, smsOptOut: $0.smsOptOut)
        }
        return QueuedSession(
            localId: UUID(),
            playedAt: fmt.string(from: playedAt),
            location: location.isEmpty ? nil : location,
            notes: notes.isEmpty ? nil : notes,
            players: players,
            enqueuedAt: Date()
        )
    }
}

struct NewSessionView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var connectivity: Connectivity
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = NewSessionModel()

    @State private var saving = false
    @State private var showAddPhone = false
    @State private var newName = ""
    @State private var newPhone = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.cream.ignoresSafeArea()
                Form {
                    detailsSection
                    selectedSection
                    pickerSection
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("New session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .bold()
                        .disabled(model.selected.isEmpty || saving)
                }
            }
            .task { await model.load(store) }
            .overlay { if saving { ProgressView("Saving…").padding().background(.thinMaterial).clipShape(RoundedRectangle(cornerRadius: 12)) } }
        }
    }

    private var detailsSection: some View {
        Section {
            DatePicker("Date", selection: $model.playedAt, displayedComponents: .date)
            TextField("Location (optional)", text: $model.location)
            TextField("Notes (optional)", text: $model.notes, axis: .vertical)
        }
    }

    private var selectedSection: some View {
        Section {
            if model.selectedPlayers.isEmpty {
                Text("No one selected yet").foregroundStyle(Theme.inkSoft)
            } else {
                ForEach(model.selectedPlayers) { p in
                    Button { model.toggle(p.id) } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.amber)
                            Text(p.name).foregroundStyle(Theme.ink)
                            if !p.hasPhone {
                                Pill(text: "no phone", color: Theme.inkSoft)
                            }
                            Spacer()
                        }
                    }
                }
            }
        } header: {
            HStack {
                Text("Selected")
                Spacer()
                Text("\(model.selectedCount) selected")
                    .font(Theme.mono(13, weight: .semibold))
                    .foregroundStyle(Theme.amber)
            }
        }
    }

    private var pickerSection: some View {
        Section {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.inkSoft)
                TextField("Search or add a player", text: $model.search)
                    .autocorrectionDisabled()
            }
            if model.canAddTyped {
                Button {
                    newName = model.search.trimmingCharacters(in: .whitespaces)
                    newPhone = ""
                    showAddPhone = true
                } label: {
                    Label("Add “\(model.search)”", systemImage: "plus.circle")
                        .foregroundStyle(Theme.amber)
                }
            }
            ForEach(model.filtered) { p in
                Button { model.toggle(p.id) } label: {
                    HStack {
                        Image(systemName: "circle").foregroundStyle(Theme.inkSoft)
                        Text(p.name).foregroundStyle(Theme.ink)
                        Spacer()
                        if !p.hasPhone { Pill(text: "no phone", color: Theme.inkSoft) }
                    }
                }
            }
        } header: {
            Text("Add players")
        }
        .sheet(isPresented: $showAddPhone) { addPlayerSheet }
    }

    private var addPlayerSheet: some View {
        NavigationStack {
            Form {
                Section("New player") {
                    TextField("Name", text: $newName)
                    TextField("Phone (optional)", text: $newPhone)
                        .keyboardType(.phonePad)
                }
                Section {
                    Text("A phone number lets this player receive the SMS rating link. You can add it later in Roster.")
                        .font(.footnote).foregroundStyle(Theme.inkSoft)
                }
            }
            .navigationTitle("Add player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showAddPhone = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let n = newName.trimmingCharacters(in: .whitespaces)
                        guard !n.isEmpty else { return }
                        model.addInline(name: n, phone: newPhone.isEmpty ? nil : newPhone)
                        showAddPhone = false
                    }.bold().disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        saving = true
        let item = model.makeQueued()
        Task {
            // Try an immediate online write; fall back to the durable queue.
            if connectivity.isOnline {
                do {
                    _ = try await store.createSession(from: item)
                    saving = false; dismiss(); return
                } catch {
                    store.queue.enqueue(item)   // network hiccup — don't lose the roster
                }
            } else {
                store.queue.enqueue(item)
            }
            saving = false
            dismiss()
        }
    }
}
