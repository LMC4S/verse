import Foundation
import UserNotifications

enum Notify {
    /// Posts a user notification, respecting the in-app toggle. Best effort:
    /// if the user denied notification permission, this silently does nothing
    /// (the panel already shows the outcome).
    static func post(title: String, body: String) {
        guard AppSettings.load().notifications else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            center.add(UNNotificationRequest(
                identifier: UUID().uuidString, content: content, trigger: nil
            ))
        }
    }
}
