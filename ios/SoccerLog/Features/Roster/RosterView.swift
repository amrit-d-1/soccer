import SwiftUI

@MainActor
final class RosterModel: ObservableObject {
    @Published var players: [Player] = []
    @Published var counts: [UUID: Int] = [:]
    @Published var loading = false
    @Published var error: String?

    func load(_ store: DataStore) async {
        loading = true; error = nil
        do {
            async let p = store.fetchPlayers()
            async let c = store.fetchAppearanceCounts()
            players = try await p
            counts = try await c
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

struct RosterView: View {
    @EnvironmentObject var store: DataStore
    @StateObject private var model = RosterModel()

    @State private var showAdd = false
    @State private var editing: Player?
    @State private var showImport = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.cream.ignoresSafeArea()
                List {
                    if let e = model.error {
                        Text(e).foregroundStyle(.red).font(.footnote)
                    }
                    ForEach(model.players) { p in
                        Button { editing = p } label: { row(p) }
                            .listRowBackground(Theme.card)
                    }
                }
                .scrollContentBackground(.hidden)
                .overlay { if model.loading && model.players.isEmpty { ProgressView() } }
            }
            .navigationTitle("Roster")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showAdd = true } label: { Label("Add player", systemImage: "plus") }
                        Button { showImport = true } label: { Label("Import from Contacts", systemImage: "person.crop.circle.badge.plus") }
                    } label: { Image(systemName: "plus.circle.fill") }
                }
            }
            .sheet(isPresented: $showAdd, onDismiss: reload) { EditPlayerSheet(player: nil) }
            .sheet(item: $editing, onDismiss: reload) { EditPlayerSheet(player: $0) }
            .sheet(isPresented: $showImport, onDismiss: reload) { ContactsImportView() }
            .task { await model.load(store) }
            .refreshable { await model.load(store) }
        }
    }

    private func row(_ p: Player) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(p.name).foregroundStyle(p.isActive ? Theme.ink : Theme.inkSoft)
                    if !p.isActive { Pill(text: "inactive", color: Theme.inkSoft) }
                    if p.smsOptOut { Pill(text: "opted out", color: Theme.warn) }
                }
                if let ph = p.phone, !ph.isEmpty {
                    Text(ph).font(Theme.mono(12)).foregroundStyle(Theme.inkSoft)
                } else {
                    Text("no phone").font(.caption).foregroundStyle(Theme.inkSoft)
                }
            }
            Spacer()
            Text("\(model.counts[p.id] ?? 0)")
                .font(Theme.mono(15, weight: .semibold)).foregroundStyle(Theme.ink)
            Text("games").font(.caption2).foregroundStyle(Theme.inkSoft)
        }
    }

    private func reload() { Task { await model.load(store) } }
}

/// Add / edit a single player.
struct EditPlayerSheet: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) private var dismiss
    let player: Player?

    @State private var name = ""
    @State private var phone = ""
    @State private var isActive = true
    @State private var optOut = false
    @State private var busy = false

    var isEdit: Bool { player != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Phone (optional)", text: $phone).keyboardType(.phonePad)
                }
                if isEdit {
                    Section {
                        Toggle("Active", isOn: $isActive)
                        Toggle("SMS opted out", isOn: $optOut)
                    } footer: {
                        Text("Opted-out players never receive rating-request texts.")
                    }
                }
            }
            .navigationTitle(isEdit ? "Edit player" : "Add player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.bold()
                        .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let p = player {
                    name = p.name; phone = p.phone ?? ""
                    isActive = p.isActive; optOut = p.smsOptOut
                }
            }
        }
    }

    private func save() {
        busy = true
        let n = name.trimmingCharacters(in: .whitespaces)
        Task {
            do {
                if let p = player {
                    try await store.updatePlayer(p.id, PlayerUpdate(
                        name: n,
                        phone: Phone.normalize(phone),
                        isActive: isActive,
                        smsOptOut: optOut))
                } else {
                    _ = try await store.addPlayer(name: n, phone: phone.isEmpty ? nil : phone)
                }
                dismiss()
            } catch { busy = false }
        }
    }
}
