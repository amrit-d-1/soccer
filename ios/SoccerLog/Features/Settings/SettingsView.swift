import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var connectivity: Connectivity

    @AppStorage("reminderEnabled") private var reminderEnabled = true
    @AppStorage("reminderWeekday") private var reminderWeekday = 6   // Friday (1=Sun)
    @AppStorage("reminderHour") private var reminderHour = 21
    @AppStorage("reminderMinute") private var reminderMinute = 0

    private let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                var c = DateComponents(); c.hour = reminderHour; c.minute = reminderMinute
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { newValue in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                reminderHour = c.hour ?? 21
                reminderMinute = c.minute ?? 0
                reschedule()
            }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.cream.ignoresSafeArea()
                Form {
                    Section("Weekly reminder") {
                        Toggle("Remind me to log the game", isOn: $reminderEnabled)
                            .onChange(of: reminderEnabled) { _, _ in reschedule() }
                        if reminderEnabled {
                            Picker("Day", selection: $reminderWeekday) {
                                ForEach(1...7, id: \.self) { Text(weekdays[$0 - 1]).tag($0) }
                            }
                            .onChange(of: reminderWeekday) { _, _ in reschedule() }
                            DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
                        }
                    } footer: {
                        Text("A local notification. Tapping it opens a new session.")
                    }

                    Section("Connection") {
                        HStack {
                            Text("Status")
                            Spacer()
                            Pill(text: connectivity.isOnline ? "Online" : "Offline",
                                 color: connectivity.isOnline ? Theme.good : Theme.warn)
                        }
                        if !store.queue.pending.isEmpty {
                            HStack {
                                Text("Pending sync")
                                Spacer()
                                Text("\(store.queue.pending.count)").font(Theme.mono(14))
                            }
                        }
                    }

                    Section {
                        Button(role: .destructive) {
                            Task { await store.signOut() }
                        } label: { Text("Sign out") }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .task { reschedule() }
        }
    }

    private func reschedule() {
        Task {
            if reminderEnabled {
                await NotificationManager.shared.schedule(
                    weekday: reminderWeekday, hour: reminderHour, minute: reminderMinute)
            } else {
                NotificationManager.shared.cancel()
            }
        }
    }
}
