import AppKit
import StoatFeatures
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        observeSystemPower()
    }

    /// Sleep and wake are the two connection-relevant events the realtime client cannot observe
    /// for itself: it only ever reacts to its own socket failing, and a Mac usually wakes onto a
    /// different network than it slept on. AppKit stays in the app target; `SystemPowerCenter` is
    /// the seam these post through, mirroring how `AppLifecycleCenter` already works.
    private func observeSystemPower() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { SystemPowerCenter.shared.note(.willSleep) }
        }
        center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { SystemPowerCenter.shared.note(.didWake) }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppLifecycleCenter.shared.update(.active)
    }

    func applicationWillResignActive(_ notification: Notification) {
        AppLifecycleCenter.shared.update(.inactive)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let route = NotificationRoute(userInfo: response.notification.request.content.userInfo) else { return }
        await MainActor.run {
            NotificationRouteCenter.shared.open(route)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        []
    }
}
