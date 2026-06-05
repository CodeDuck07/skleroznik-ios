//
//  AppNotificationDelegate.swift
//  склерозник
//

import SwiftUI
import UserNotifications

/// Ключ userInfo в UNNotificationContent — совпадает с identifier запроса (UUID строкой).
enum ReminderNotificationPayload {
    static let reminderIdKey = "reminderId"
}

/// Проброс открытия деталей из пуша в SwiftUI.
final class NotificationRouter: ObservableObject {
    @Published var pendingOpenReminderId: UUID?
}

protocol ReminderNotificationAttach: AnyObject {
    func attach(router: NotificationRouter)
}

private struct ReminderNotificationAttachKey: EnvironmentKey {
    static let defaultValue: (any ReminderNotificationAttach)? = nil
}

extension EnvironmentValues {
    var reminderNotificationAttach: (any ReminderNotificationAttach)? {
        get { self[ReminderNotificationAttachKey.self] }
        set { self[ReminderNotificationAttachKey.self] = newValue }
    }
}

#if os(iOS) || os(visionOS)
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, ReminderNotificationAttach {
    weak var router: NotificationRouter?
    private var bufferedReminderId: UUID?

    func attach(router: NotificationRouter) {
        self.router = router
        guard let id = bufferedReminderId else { return }
        bufferedReminderId = nil
        DispatchQueue.main.async {
            router.pendingOpenReminderId = id
        }
    }

    private func enqueueOpenReminder(id: UUID) {
        DispatchQueue.main.async {
            if let router = self.router {
                router.pendingOpenReminderId = id
            } else {
                self.bufferedReminderId = id
            }
        }
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        guard let raw = response.notification.request.content.userInfo[ReminderNotificationPayload.reminderIdKey] as? String,
              let id = UUID(uuidString: raw)
        else { return }
        enqueueOpenReminder(id: id)
    }
}
#endif
