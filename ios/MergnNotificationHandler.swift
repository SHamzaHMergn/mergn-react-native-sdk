import Foundation
import UIKit
import UserNotifications
import mergn_ios

/// Reports notification impressions and taps to the Mergn SDK, and keeps the
/// SDK's current view controller up to date so in-app popups have somewhere to
/// present.
///
/// Mergn's reference iOS integration puts these calls directly in the host
/// app's AppDelegate:
///
///     UNUserNotificationCenter.current().delegate = self
///     SDKManager.shared.setCurrentViewController(rootViewController)
///
///     func userNotificationCenter(_:willPresent:withCompletionHandler:) {
///       EventManager.shared.notificationViewed(notificationData: notification.request)
///     }
///     func userNotificationCenter(_:didReceive response:withCompletionHandler:) {
///       EventManager.shared.notificationTapped(notificationData: response.notification.request)
///     }
///
/// A React Native app cannot follow that pattern as-is: expo-notifications and
/// @react-native-firebase both claim `UNUserNotificationCenter.delegate`, and
/// whichever loads last wins. Assigning it here would silently break their
/// notification handling (and vice versa).
///
/// So instead of owning the delegate, this observes it. `swizzle()` wraps any
/// existing delegate's two methods, forwards to Mergn, then calls the original
/// implementation — so Mergn tracking is additive and the app's own handling is
/// untouched. On Android the SDK does this inside its own
/// FireBaseMessagingService, which is why there is no JS API for it on either
/// platform: both are automatic.
@objc(MergnNotificationHandler)
public final class MergnNotificationHandler: NSObject {

  @objc public static let shared = MergnNotificationHandler()

  private var installed = false

  /// Called from the module's `+load`-time hook, after the JS bridge is up so
  /// that whichever notification library the app uses has already claimed the
  /// delegate.
  @objc public func install() {
    guard !installed else { return }
    installed = true

    // The SDK needs a live view controller for in-app popups. Refresh it now and
    // again whenever the app returns to the foreground, since the top-most
    // controller changes as the user navigates.
    refreshViewController()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(refreshViewController),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )

    observeNotificationCenterDelegate()
  }

  @objc private func refreshViewController() {
    DispatchQueue.main.async {
      if let top = UIApplication.topViewController() {
        SDKManager.shared.setCurrentViewController(top)
      }
    }
  }

  // MARK: - Delegate observation

  private func observeNotificationCenterDelegate() {
    let center = UNUserNotificationCenter.current()

    guard let delegate = center.delegate else {
      // Nothing else claimed the delegate, so take it ourselves. This is the
      // plain-RN case with no notification library installed.
      center.delegate = FallbackDelegate.shared
      return
    }

    swizzle(type(of: delegate))
  }

  /// Wraps the delegate's willPresent / didReceive so Mergn sees every
  /// notification without displacing the existing handler.
  private func swizzle(_ cls: AnyClass) {
    swizzleWillPresent(cls)
    swizzleDidReceive(cls)
  }

  private func swizzleWillPresent(_ cls: AnyClass) {
    let selector = #selector(
      UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:withCompletionHandler:)
    )
    guard let original = class_getInstanceMethod(cls, selector) else { return }

    typealias Impl = @convention(c) (
      AnyObject, Selector, UNUserNotificationCenter, UNNotification,
      @escaping (UNNotificationPresentationOptions) -> Void
    ) -> Void
    let originalImp = unsafeBitCast(method_getImplementation(original), to: Impl.self)

    let block: @convention(block) (
      AnyObject, UNUserNotificationCenter, UNNotification,
      @escaping (UNNotificationPresentationOptions) -> Void
    ) -> Void = { receiver, center, notification, completion in
      EventManager.shared.notificationViewed(notificationData: notification.request)
      originalImp(receiver, selector, center, notification, completion)
    }

    method_setImplementation(original, imp_implementationWithBlock(block))
  }

  private func swizzleDidReceive(_ cls: AnyClass) {
    let selector = #selector(
      UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:)
    )
    guard let original = class_getInstanceMethod(cls, selector) else { return }

    typealias Impl = @convention(c) (
      AnyObject, Selector, UNUserNotificationCenter, UNNotificationResponse,
      @escaping () -> Void
    ) -> Void
    let originalImp = unsafeBitCast(method_getImplementation(original), to: Impl.self)

    let block: @convention(block) (
      AnyObject, UNUserNotificationCenter, UNNotificationResponse, @escaping () -> Void
    ) -> Void = { receiver, center, response, completion in
      EventManager.shared.notificationTapped(notificationData: response.notification.request)
      originalImp(receiver, selector, center, response, completion)
    }

    method_setImplementation(original, imp_implementationWithBlock(block))
  }

  /// Used only when no other delegate exists, so notifications still surface and
  /// get reported.
  private final class FallbackDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = FallbackDelegate()

    func userNotificationCenter(
      _ center: UNUserNotificationCenter,
      willPresent notification: UNNotification,
      withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
      EventManager.shared.notificationViewed(notificationData: notification.request)
      completionHandler([.banner, .list, .sound, .badge])
    }

    func userNotificationCenter(
      _ center: UNUserNotificationCenter,
      didReceive response: UNNotificationResponse,
      withCompletionHandler completionHandler: @escaping () -> Void
    ) {
      EventManager.shared.notificationTapped(notificationData: response.notification.request)
      completionHandler()
    }
  }
}
