import SwiftUI

@main
struct ReminderNotesApp: App {
    #if os(iOS) || os(visionOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif
    @StateObject private var notificationRouter = NotificationRouter()

    var body: some Scene {
        WindowGroup {
            #if os(iOS) || os(visionOS)
            ContentView(notificationRouter: notificationRouter)
                .environment(\.reminderNotificationAttach, appDelegate)
            #else
            ContentView(notificationRouter: notificationRouter)
            #endif
        }
    }
}
