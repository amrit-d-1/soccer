import SwiftUI
import Contacts
import ContactsUI

/// A candidate row derived from a picked contact.
struct ContactCandidate: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var phone: String?        // normalized E.164
    var contactId: String
    var skipReason: String?   // nil => will be added
}

@MainActor
final class ContactsImportModel: ObservableObject {
    enum Stage { case picking, confirming, importing, done, denied }
    @Published var stage: Stage = .picking
    @Published var candidates: [ContactCandidate] = []
    @Published var addedCount = 0
    @Published var error: String?

    var toAdd: [ContactCandidate] { candidates.filter { $0.skipReason == nil } }
    var toSkip: [ContactCandidate] { candidates.filter { $0.skipReason != nil } }

    func checkPermission() {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .denied || status == .restricted { stage = .denied }
    }

    /// Build candidates from picked contacts, deduping against the existing roster.
    func process(_ contacts: [CNContact], store: DataStore) async {
        let existing = (try? await store.fetchPlayers()) ?? []
        let existingContactIds = Set(existing.compactMap { $0.contactId })
        let existingPhones = Set(existing.compactMap { $0.phone }.filter { !$0.isEmpty })

        var seenPhones = Set<String>()
        var seenContacts = Set<String>()
        var result: [ContactCandidate] = []

        for c in contacts {
            let name = displayName(c)
            let phone = Phone.normalize(firstMobile(c))
            let cid = c.identifier

            var reason: String?
            if existingContactIds.contains(cid) || seenContacts.contains(cid) {
                reason = "already in roster"
            } else if let ph = phone, existingPhones.contains(ph) || seenPhones.contains(ph) {
                reason = "duplicate phone"
            } else if name.isEmpty {
                reason = "no name"
            }
            seenContacts.insert(cid)
            if let ph = phone { seenPhones.insert(ph) }
            result.append(ContactCandidate(name: name, phone: phone, contactId: cid, skipReason: reason))
        }
        candidates = result.sorted { $0.name.lowercased() < $1.name.lowercased() }
        stage = .confirming
    }

    func confirmImport(_ store: DataStore) async {
        stage = .importing
        let inserts = toAdd.map { PlayerInsert(name: $0.name, phone: $0.phone, contactId: $0.contactId) }
        do {
            try await store.importPlayers(inserts)
            addedCount = inserts.count
            stage = .done
        } catch {
            self.error = error.localizedDescription
            stage = .confirming
        }
    }

    private func displayName(_ c: CNContact) -> String {
        let full = [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        if !full.isEmpty { return full }
        return c.organizationName
    }

    private func firstMobile(_ c: CNContact) -> String? {
        // Prefer a mobile/iPhone number; otherwise the first number available.
        if let mobile = c.phoneNumbers.first(where: {
            $0.label == CNLabelPhoneNumberMobile || $0.label == CNLabelPhoneNumberiPhone
        }) { return mobile.value.stringValue }
        return c.phoneNumbers.first?.value.stringValue
    }
}

struct ContactsImportView: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = ContactsImportModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.cream.ignoresSafeArea()
                switch model.stage {
                case .picking:
                    ContactPicker(
                        onPicked: { contacts in
                            Task { await model.process(contacts, store: store) }
                        },
                        onCancel: { dismiss() }
                    )
                    .ignoresSafeArea()
                case .confirming, .importing:
                    confirmList
                case .done:
                    doneView
                case .denied:
                    deniedView
                }
            }
            .navigationTitle("Import contacts")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { model.checkPermission() }
        }
    }

    private var confirmList: some View {
        VStack(spacing: 0) {
            List {
                if let e = model.error { Text(e).foregroundStyle(.red).font(.footnote) }
                Section("Will add (\(model.toAdd.count))") {
                    ForEach(model.toAdd) { c in
                        HStack {
                            Text(c.name)
                            Spacer()
                            Text(c.phone ?? "no phone").font(Theme.mono(12)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                }
                if !model.toSkip.isEmpty {
                    Section("Skipped (\(model.toSkip.count))") {
                        ForEach(model.toSkip) { c in
                            HStack {
                                Text(c.name.isEmpty ? "(no name)" : c.name).foregroundStyle(Theme.inkSoft)
                                Spacer()
                                Pill(text: c.skipReason ?? "skipped", color: Theme.inkSoft)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)

            Button {
                Task { await model.confirmImport(store) }
            } label: {
                if model.stage == .importing { ProgressView().tint(.white) }
                else { Text("Add \(model.toAdd.count) player\(model.toAdd.count == 1 ? "" : "s")") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.toAdd.isEmpty || model.stage == .importing)
            .padding()
        }
    }

    private var doneView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 52)).foregroundStyle(Theme.good)
            Text("Added \(model.addedCount) player\(model.addedCount == 1 ? "" : "s")")
                .font(.headline).foregroundStyle(Theme.ink)
            Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 40)
        }
    }

    private var deniedView: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.circle").font(.system(size: 48)).foregroundStyle(Theme.inkSoft)
            Text("Contacts access is off").font(.headline).foregroundStyle(Theme.ink)
            Text("Enable Contacts for SoccerLog in Settings to import, or add players by hand from the Roster screen.")
                .multilineTextAlignment(.center).font(.subheadline).foregroundStyle(Theme.inkSoft)
                .padding(.horizontal, 24)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }.buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 40)
            Button("Cancel") { dismiss() }.foregroundStyle(Theme.inkSoft)
        }
    }
}

/// Wraps CNContactPickerViewController in multi-select mode.
struct ContactPicker: UIViewControllerRepresentable {
    var onPicked: ([CNContact]) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIViewController {
        let host = UIViewController()
        DispatchQueue.main.async {
            let picker = CNContactPickerViewController()
            picker.delegate = context.coordinator
            host.present(picker, animated: true)
        }
        return host
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let parent: ContactPicker
        var didFinish = false
        init(_ parent: ContactPicker) { self.parent = parent }

        // Implementing the array variant enables multi-select ("Done" button).
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            didFinish = true
            parent.onPicked(contacts)
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            if !didFinish { parent.onCancel() }
        }
    }
}
