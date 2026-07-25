import Foundation
import Combine
import UserNotifications

/// Local-only weekly reminder to log the game. No push infrastructure.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    /// Fires when the reminder notification is tapped, so the app can open
    /// straight into the New Session screen.
    let openNewSession = PassthroughSubject<Void, Never>()

    private let identifier = "weekly-log-reminder"
    private let categoryId = "LOG_GAME"

    private override init() { super.init() }

    func registerCategories() {
        UNUserNotificationCenter.current().delegate = self
        let category = UNNotificationCategory(identifier: categoryId, actions: [],
                                              intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Schedule (or reschedule) the weekly reminder. `weekday` is 1=Sun…7=Sat.
    func schedule(weekday: Int, hour: Int, minute: Int) async {
        let granted = await requestAuthorization()
        guard granted else { return }
        cancel()

        var comps = DateComponents()
        comps.weekday = weekday
        comps.hour = hour
        comps.minute = minute

        let content = UNMutableNotificationContent()
        content.title = "Log tonight’s game"
        content.body = "Who played and how did it go?"
        content.sound = .default
        content.categoryIdentifier = categoryId

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    // Show the alert even in foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .sound] }

    // Tapping the reminder opens the New Session screen.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        if response.notification.request.identifier == identifier {
            await MainActor.run { openNewSession.send(()) }
        }
    }
}
