# iOS setup

> **Not using Expo?** This page assumes an Expo project. For bare React
> Native, see [BARE-REACT-NATIVE.md](./BARE-REACT-NATIVE.md) — the module
> autolinks either way, but bare projects configure the native side by hand.

```sh
npm install mergn-react-native
```

```json
{ "expo": { "plugins": ["mergn-react-native"] } }
```

```sh
npx expo prebuild --platform ios
cd ios && pod install && cd ..
npx expo run:ios
```

## What the package does for you

| | |
| --- | --- |
| Native module registration | Autolinking (`mergn-react-native.podspec`) |
| MERGN iOS SDK | `mergn_ios.xcframework`, bundled — nothing to download |
| `ios.deploymentTarget` raised to 14.0 | Config plugin (only ever raised, never lowered) |
| `ios.useFrameworks: "static"` | Config plugin |
| `pod 'MergnSDK'` in your Podfile | Config plugin |
| Notification view / click tracking | Automatic (see below) |

You do **not** edit your `Podfile` or `AppDelegate`.

### Why those two build settings are needed

- **iOS 14.0** — the framework is built for iOS 14. Expo's template defaults to
  13.4, which fails with *"they required a higher minimum deployment target"*.
- **`useFrameworks: "static"`** — the SDK ships a Swift module with no
  Objective-C headers, so without `use_frameworks!` the build fails with
  *"Unable to resolve module dependency: 'mergn_ios'"*. `static` is chosen
  because Firebase's Swift pods also require it.

Both are applied automatically. If your app already targets a newer iOS, that is
left alone.

## Push notifications

```sh
npx expo install @react-native-firebase/app @react-native-firebase/messaging
```

1. Register your app's **bundle ID** in the Firebase console and download
   `GoogleService-Info.plist`.
2. Wire it up in `app.json`:
   ```json
   {
     "expo": {
       "ios": {
         "googleServicesFile": "./GoogleService-Info.plist",
         "entitlements": { "aps-environment": "development" }
       },
       "plugins": [
         "mergn-react-native",
         "@react-native-firebase/app"
       ]
     }
   }
   ```
3. Upload an **APNs key** (`.p8`) to Firebase → Project settings → Cloud
   Messaging. This needs a paid Apple Developer account.
4. Pass the token to MERGN:
   ```js
   const token = await messaging().getToken();
   await Mergn.setFirebaseToken(token);
   ```

Without `GoogleService-Info.plist`, `messaging()` throws
`No Firebase App '[DEFAULT]' has been created`. Everything else in this package
keeps working — only FCM is affected.

> APNs cannot be used on the iOS Simulator. Real push delivery requires a
> physical device. To test *handling* without APNs, inject a payload locally:
> ```sh
> xcrun simctl push booted <your.bundle.id> payload.json
> ```
> The payload needs `aps` at the top level (raw APNs shape). An FCM v1 request —
> the JSON you POST to Firebase, with a top-level `message` — will be rejected
> with *"Notification payload is missing the aps key"*, because only Firebase's
> servers unwrap that envelope.

### Notification view / click tracking

Automatic — no JS API and no AppDelegate changes.

MERGN's iOS SDK expects the host app to call `notificationViewed` and
`notificationTapped` from the `UNUserNotificationCenter` delegate. A React Native
app cannot simply assign that delegate: `expo-notifications` and
`@react-native-firebase` both claim it, and the last one to load wins.

So this package **wraps** whichever delegate your app ends up with, forwards the
two events to MERGN, then calls the original implementation. Your own
notification handling is untouched, and tracking is additive.

It also refreshes the SDK's current view controller whenever the app comes to the
foreground, which is what in-app popups need.

## In-app popups

Triggered by MERGN campaigns in response to events:

```js
await Mergn.performEvent("Collection Viewed", { title: "Beauty" });
```

The package keeps `SDKManager.shared.setCurrentViewController(...)` up to date,
so popups have somewhere to present. If none appears, confirm a campaign is
configured for that event name in your MERGN dashboard.

## Rich push images (optional)

iOS renders a notification image only if your app contains a **Notification
Service Extension** — a separate binary that must be a target of *your* app, so
no library can supply it. Without one, a push carrying `mutable-content: 1` and
an `image` URL still arrives, just as text.

To add it:

1. **Xcode → File → New → Target → Notification Service Extension**, name it
   `NotificationService`.
2. Replace the generated `NotificationService.swift` with the reference
   implementation:
   `node_modules/mergn-react-native/ios/NotificationService/NotificationService.swift`
3. Set the extension's **iOS Deployment Target to match your app** — Xcode
   defaults it to the latest SDK, and an extension must not require a newer OS
   than its host.

Because `expo prebuild --clean` regenerates the Xcode project, commit your `ios/`
directory (as you would `android/`) or re-add the target after a clean prebuild.

Android needs none of this — the MERGN SDK handles images itself there.

## Troubleshooting

**`Unable to resolve module dependency: 'mergn_ios'`** — `use_frameworks!` is not
active. Ensure `mergn-react-native` is in your `app.json` plugins, then
`npx expo prebuild --platform ios` and `pod install` again.

**`they required a higher minimum deployment target`** — same cause; the plugin
sets iOS 14.0 for you.

**`Unable to find compatibility version string for object version 70`** —
Xcode 16/26 wrote a project format your CocoaPods cannot read. The plugin pins it
back on prebuild; alternatively update CocoaPods.

**`Cycle inside <YourApp>`** — `@react-native-firebase`'s script phase declares
your built `Info.plist` as an input, which cycles once an app extension is
embedded. The plugin clears that input; re-run prebuild.

**`MergnModule.<method> is unavailable`** — native module not loaded. Expo Go
cannot load native code; use `npx expo run:ios` or an EAS build.
