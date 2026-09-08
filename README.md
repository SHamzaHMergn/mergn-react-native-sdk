# mergn-react-native

MERGN SDK for React Native. One JS API, native SDKs on both platforms.

## Install

```sh
npm install mergn-react-native
```

Add the plugin to `app.json`:

```json
{
  "expo": {
    "plugins": ["mergn-react-native"]
  }
}
```

Then rebuild the native projects:

```sh
npx expo prebuild
npx expo run:android
npx expo run:ios      # macOS only
```

That's it. The Android `.aar` and the iOS `.xcframework` ship inside this
package, and autolinking registers the native module — you do not edit
`MainApplication`, `settings.gradle`, or the `Podfile`.

> **Expo Go will not work.** This package contains native code, so it needs a
> development build (`expo run:*`) or an EAS build.

## Usage

```js
import Mergn from "mergn-react-native";

// Once, as early as possible — pending events are dropped until this resolves.
await Mergn.registerApi("YOUR_MERGN_API_KEY");

await Mergn.performEvent("Collection Viewed", { title: "Beauty" });
await Mergn.setAttribute("Email", "user@example.com");
await Mergn.login("user@example.com");
await Mergn.setFirebaseToken(fcmToken);
```

Every method returns a Promise resolving to a status string from the native SDK.
Identical method names, arguments and results on Android and iOS.

| Method | Purpose |
| --- | --- |
| `registerApi(apiKey)` | Register your API key. Call first. |
| `performEvent(name, props?)` | Record an event. |
| `setAttribute(name, value)` | Set a user attribute. |
| `login(id)` | Identify the user. |
| `setFirebaseToken(token)` | Give MERGN the push token. |
| `setAppContext(token)` | Currently the same path as `setFirebaseToken`. |

### `setAttribute` de-duplicates

Sending the same value twice for one attribute is a deliberate no-op in the SDK
("value is same as previous"). Use a changed value when testing.

## Push notifications

You need Firebase configured in your own app — this package does not bundle it.

```sh
npx expo install @react-native-firebase/app @react-native-firebase/messaging
```

- **Android:** put `google-services.json` in your project and configure the
  Firebase plugin. This package's config plugin already declares MERGN's
  messaging service and the notification permissions.
- **iOS:** add `GoogleService-Info.plist`, upload an APNs key to Firebase, and
  add the push capability. Register the app's bundle ID in Firebase.

Pass the token you get from `messaging().getToken()` to
`Mergn.setFirebaseToken(token)`.

### Rich push images on iOS (optional)

iOS only renders a notification image if the app contains a **Notification
Service Extension** — a separate binary that must be a target of your app, so
no library can provide it. Without one, a push carrying `mutable-content: 1`
and an `image` URL still arrives, just as text.

To add it: **Xcode → File → New → Target → Notification Service Extension**,
then copy the implementation from
`node_modules/mergn-react-native/ios/NotificationService/NotificationService.swift`.
Set the extension's deployment target to match your app (it must not be higher).

Android needs nothing here — MERGN's SDK handles images itself.

## Platform guides

| | |
| --- | --- |
| [docs/ANDROID.md](docs/ANDROID.md) | Android setup, push, popups, troubleshooting |
| [docs/IOS.md](docs/IOS.md) | iOS setup, push, rich images, troubleshooting |
| [docs/BARE-REACT-NATIVE.md](docs/BARE-REACT-NATIVE.md) | **Setup without Expo** — bare React Native, step by step |
| [docs/MIGRATION.md](docs/MIGRATION.md) | **Upgrading from a manual integration — read this first if you copied MergnModule.java into your app** |

## Requirements

| | |
| --- | --- |
| iOS | 14.0+, device and simulator |
| Android | minSdk 24+ |
| React Native | 0.72+ (verified on 0.74.5 and 0.76.5) |
| Expo | SDK 50+ — **optional**, see [BARE-REACT-NATIVE.md](docs/BARE-REACT-NATIVE.md) |
| Architecture | Old and new (new via React Native's interop layer) |
| Expo Go | Not supported — cannot load native modules |
| macOS / tvOS / visionOS / Web | Not supported |

## Troubleshooting

**`MergnModule.<method> is unavailable`** — the native module did not load.
Rebuild (`npx expo prebuild && npx expo run:ios`). Expo Go cannot load it.

**`pod install` fails with "Unable to find compatibility version string for
object version 70"** — newer Xcode writes a project format older CocoaPods
cannot read. This package's config plugin pins it; make sure the plugin is in
your `app.json` and re-run `npx expo prebuild`. Or update CocoaPods.

**iOS build fails with "Cycle inside <YourApp>"** — caused by
`@react-native-firebase`'s script phase once an app extension is embedded. The
config plugin fixes this too; ensure it is listed in `app.json`.

**Events reach the SDK but nothing appears in the dashboard** — check
`registerApi` resolved before you sent them, and confirm your API key and
bundle ID / package name are provisioned in your MERGN account.
