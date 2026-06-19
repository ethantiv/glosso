import UserNotifications

/// Posts a transient system notification — the only feedback the headless fix-grammar
/// path (issue #46) has, fired on a missing selection or an app switch, never on success.
/// ponytail: UNUserNotificationCenter; swap for NSBeep if the permission prompt is unwanted.
enum SystemUserNotifier {
    /// `identifier` defaults to a one-off UUID; pass a stable id (e.g. the update
    /// dymek's) so a `UNUserNotificationCenterDelegate` can recognise the tap.
    static func post(_ body: String, identifier: String = UUID().uuidString) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Glosso"
            content.body = body
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }
}
