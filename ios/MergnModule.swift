import Foundation
import React
import UIKit
import mergn_ios

// iOS counterpart of android/app/src/main/java/com/android/test/MergnModule.java.
// The JS side (MergnModule.js) funnels everything through one method:
//   performAction(action, jsonData) -> Promise
// so the same action strings must be honoured here. Written in Swift because
// mergn_ios ships only a .swiftmodule (no Objective-C headers), so ObjC cannot
// import it.
@objc(MergnModule)
class MergnModule: NSObject {

  private enum Action {
    static let registerApi        = "register_api"
    static let performEvent       = "perform_event"
    static let setAttribute       = "add_attribute"
    static let login              = "login_mergn"
    static let firebaseToken      = "firebase_token_mergn"
    static let appContext         = "mergn_app_context"
  }

  private let manager = EventManager.shared

  // Matches the Android module: the SDK is a singleton, so re-registering the
  // API key on every call would be wasted work. Tracked only to log it.
  private static var didRegister = false

  @objc static func requiresMainQueueSetup() -> Bool { true }

  override init() {
    super.init()
    // Install notification tracking once the module is constructed. By this
    // point expo-notifications / RNFB have claimed UNUserNotificationCenter's
    // delegate, so the handler wraps theirs instead of replacing it.
    // Deferred to main because it touches UIKit.
    DispatchQueue.main.async {
      MergnNotificationHandler.shared.install()
    }
  }

  /// The SDK renders in-app popups, so it needs a live view controller. Android
  /// gets this from getCurrentActivity(); on iOS we hand the SDK the top-most
  /// view controller before any call that might present UI.
  private func refreshTopViewController() {
    if let top = UIApplication.topViewController() {
      SDKManager.shared.setCurrentViewController(top)
    }
  }

  @objc(performAction:jsonData:resolver:rejecter:)
  func performAction(_ action: String,
                     jsonData: String,
                     resolver resolve: @escaping RCTPromiseResolveBlock,
                     rejecter reject: @escaping RCTPromiseRejectBlock) {

    // Everything here can touch UIKit (popups, view controllers), so stay on main.
    DispatchQueue.main.async {
      let options: [String: Any]
      do {
        guard let data = jsonData.data(using: .utf8),
              let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
          throw NSError(domain: "MergnModule", code: 1,
                        userInfo: [NSLocalizedDescriptionKey:
                                     "jsonData is not a JSON object: \(jsonData)"])
        }
        options = parsed
      } catch {
        NSLog("[MergnModule] performAction failed to parse payload for \(action): \(error)")
        reject("MERGN_ERROR", error.localizedDescription, error)
        return
      }

      func requireString(_ key: String) throws -> String {
        guard let value = options[key] as? String else {
          throw NSError(domain: "MergnModule", code: 2,
                        userInfo: [NSLocalizedDescriptionKey:
                                     "Missing required string '\(key)' for action '\(action)'"])
        }
        return value
      }

      do {
        switch action {

        case Action.registerApi:
          let apiKey = try requireString("apiKey")
          self.refreshTopViewController()
          self.manager.registerAPI(clientApiKey: apiKey)
          MergnModule.didRegister = true
          NSLog("[MergnModule] Registered API key")
          resolve("API Key Registered")

        case Action.performEvent:
          let eventName = try requireString("eventName")
          // Android stringifies every property value; the iOS SDK takes
          // [String: Any], so pass the JSON values through as-is.
          let properties = options["eventPropertiesMap"] as? [String: Any] ?? [:]
          self.refreshTopViewController()
          self.manager.sendEvent(eventName: eventName, properties: properties)
          NSLog("[MergnModule] Event Sent: \(eventName)")
          resolve("Event Performed")

        case Action.setAttribute:
          let name = try requireString("attributeName")
          let value = try requireString("attributeValue")
          self.manager.sendAttribute(attributeName: name, attributeValue: value)
          NSLog("[MergnModule] Attribute Set: \(name)")
          resolve("Attribute Set")

        case Action.login:
          let identifier = try requireString("uniqueIdentifier")
          // Android's single login() both persists the identifier and tells the
          // backend. iOS splits these, so do both:
          //   saveCustomerId    -> writes customerId to UserDefaults, so later
          //                        sendEvent calls are attributed to this user
          //   postIdentification-> POST /customer/set-identity, merging the
          //                        anonymous profile into the identified one
          // postIdentification may well save the id itself, in which case the
          // first call is a harmless duplicate write. Doing only the POST would
          // risk unattributed events, so both are called deliberately.
          _ = self.manager.saveCustomerId(customerId: identifier)
          let afterSave = self.manager.getCustomerId()
          self.manager.postIdentification(identity: identifier)
          NSLog("[MergnModule] User Logged In: \(identifier) (customerId now '\(afterSave)')")
          resolve("User Logged In")

        case Action.firebaseToken, Action.appContext:
          // Android routes both actions down the same path; keep that parity.
          let token = try requireString("fcmTokenMergn")
          _ = self.manager.saveFirebaseToken(token: token)
          self.manager.firebaseToken(token: token)
          let label = action == Action.appContext
            ? "Firebase Token in App Context Set" : "Firebase Token Set"
          NSLog("[MergnModule] \(label)")
          resolve(label)

        default:
          reject("UNSUPPORTED_ACTION", "Action \(action) is not supported.", nil)
        }
      } catch {
        NSLog("[MergnModule] performAction failed for action \(action): \(error)")
        reject("MERGN_ERROR", error.localizedDescription, error)
      }
    }
  }
}
