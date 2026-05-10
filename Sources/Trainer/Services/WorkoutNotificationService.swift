import Foundation
import AppKit
import UserNotifications

@MainActor
final class WorkoutNotificationService: NSObject, WorkoutNotifying {
    private let center: UNUserNotificationCenter
    private var hasRequestedAuthorization = false
    var debugHandler: ((String) -> Void)?

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        center.delegate = self
    }

    func requestAuthorizationIfNeeded() async {
        guard !hasRequestedAuthorization else { return }
        hasRequestedAuthorization = true

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            log(granted ? "Notification permission granted" : "Notification permission denied")
        } catch {
            hasRequestedAuthorization = false
            log("Notification permission request failed: \(error.localizedDescription)")
        }
    }

    func notificationDebugStatus() async -> String {
        let settings = await center.notificationSettings()
        let bundleID = Bundle.main.bundleIdentifier ?? "none"
        let bundleType = Bundle.main.object(forInfoDictionaryKey: "CFBundlePackageType") as? String ?? "none"
        let alertStyle = Bundle.main.object(forInfoDictionaryKey: "NSUserNotificationAlertStyle") as? String ?? "none"
        let backend = supportsUserNotifications(settings) ? "UNUserNotificationCenter" : "NSUserNotificationCenter"
        return "authorization=\(settings.authorizationStatus.debugName), alert=\(settings.alertSetting.debugName), sound=\(settings.soundSetting.debugName), backend=\(backend), bundleID=\(bundleID), package=\(bundleType), alertStyle=\(alertStyle)"
    }

    func sendWorkoutNotification(title: String, body: String) async -> String {
        await requestAuthorizationIfNeeded()

        let settings = await center.notificationSettings()
        guard supportsUserNotifications(settings) else {
            return sendLegacyNotification(title: title, body: body, reason: "authorization is \(settings.authorizationStatus.debugName), alert is \(settings.alertSetting.debugName)")
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "trainer.workout.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
            let message = "Notification sent: \(title) - \(body)"
            log(message)
            return message
        } catch {
            let message = "Notification failed: \(error.localizedDescription)"
            log(message)
            return message
        }
    }

    private func log(_ message: String) {
        debugHandler?(message)
    }

    private func supportsUserNotifications(_ settings: UNNotificationSettings) -> Bool {
        (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
            && settings.alertSetting != .notSupported
    }

    @available(macOS, introduced: 10.8, deprecated: 11.0, message: "Fallback for unsigned local app bundles when UNUserNotificationCenter is unsupported.")
    private func sendLegacyNotification(title: String, body: String, reason: String) -> String {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = body
        notification.soundName = NSUserNotificationDefaultSoundName

        NSUserNotificationCenter.default.delegate = self
        NSUserNotificationCenter.default.deliver(notification)

        let message = "Notification sent with AppKit fallback: \(title) - \(body) (\(reason))"
        log(message)
        return message
    }
}

extension WorkoutNotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

@available(macOS, introduced: 10.8, deprecated: 11.0, message: "Fallback for unsigned local app bundles when UNUserNotificationCenter is unsupported.")
extension WorkoutNotificationService: NSUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: NSUserNotificationCenter,
        shouldPresent notification: NSUserNotification
    ) -> Bool {
        true
    }
}

private extension UNAuthorizationStatus {
    var debugName: String {
        switch self {
        case .notDetermined:
            "notDetermined"
        case .denied:
            "denied"
        case .authorized:
            "authorized"
        case .provisional:
            "provisional"
        case .ephemeral:
            "ephemeral"
        @unknown default:
            "unknown"
        }
    }
}

private extension UNNotificationSetting {
    var debugName: String {
        switch self {
        case .notSupported:
            "notSupported"
        case .disabled:
            "disabled"
        case .enabled:
            "enabled"
        @unknown default:
            "unknown"
        }
    }
}
