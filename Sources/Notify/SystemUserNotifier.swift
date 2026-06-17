import UserNotifications

/// Posts a transient system notification — the only feedback the headless fix-grammar
/// path (issue #46) has, fired on a missing selection or an app switch, never on success.
/// ponytail: UNUserNotificationCenter; swap for NSBeep if the permission prompt is unwanted.
enum SystemUserNotifier {
    static func post(_ body: String) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Glosso"
            content.body = body
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }
}
