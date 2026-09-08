# Android setup

> **Not using Expo?** This page assumes an Expo project. For bare React
> Native, see [BARE-REACT-NATIVE.md](./BARE-REACT-NATIVE.md) — the module
> autolinks either way, but bare projects configure the native side by hand.

Most of this is automatic. Autolinking registers the native module, and the
config plugin adds the manifest entries — so a plain analytics integration needs
nothing on this page beyond installing.

> **Upgrading from a hand-rolled MERGN integration?** Read
> [MIGRATION.md](./MIGRATION.md) **first** and remove the old pieces. Installing
> this package on top of a manual integration fails the build, and two of the
> removal steps fail *silently* if you skip them.

```sh
npm install mergn-react-native
```

```json
{ "expo": { "plugins": ["mergn-react-native"] } }
```

```sh
npx expo prebuild --platform android
npx expo run:android
```

## What the package does for you

| | |
| --- | --- |
| Native module registration | Autolinking (`react-native.config.js`) |
| MERGN Android SDK | `com.github.SHamzaHMergn:Mergn_sdk_android:5.2.4` from JitPack |
| JitPack repository | Declared in the package's own `build.gradle` |
| `INTERNET`, `POST_NOTIFICATIONS`, `VIBRATE` permissions | Config plugin |
| MERGN `FireBaseMessagingService` | Config plugin |

You do **not** edit `MainApplication`, `settings.gradle`, or `app/build.gradle`.

## Requirements

- `minSdkVersion` 24 or higher
- Java 17 (the Android Gradle Plugin default for AGP 8+)

Override the SDK version if MERGN ships a new one before this package updates,
in `android/build.gradle`:

```gradle
ext { mergnSdkVersion = "5.2.5" }
```

## Push notifications

The MERGN SDK receives pushes through its own `FirebaseMessagingService`, which
the config plugin declares. You still need Firebase in your app:

```sh
npx expo install @react-native-firebase/app @react-native-firebase/messaging
```

1. Put `google-services.json` in your project root.
2. Point `app.json` at it and add the Firebase plugin:
   ```json
   {
     "expo": {
       "android": { "googleServicesFile": "./google-services.json" },
       "plugins": [
         "mergn-react-native",
         "@react-native-firebase/app"
       ]
     }
   }
   ```
3. Pass the token to MERGN:
   ```js
   import messaging from "@react-native-firebase/messaging";
   import Mergn from "mergn-react-native";

   const token = await messaging().getToken();
   await Mergn.setFirebaseToken(token);
   ```

`google-services.json` is client configuration that ships inside every APK, not
a server secret — committing it is normal and keeps builds reproducible.

### Android 13+ notification permission

`POST_NOTIFICATIONS` is declared for you, but it is a *runtime* permission on
API 33+, so you must still request it:

```js
import { PermissionsAndroid, Platform } from "react-native";

if (Platform.OS === "android" && Platform.Version >= 33) {
  await PermissionsAndroid.request(
    PermissionsAndroid.PERMISSIONS.POST_NOTIFICATIONS
  );
}
```

Without this, pushes are delivered but silently not displayed.

### Notification view / click tracking

Automatic. The SDK's own `FirebaseMessagingService` records impressions and taps
internally — there is no JS API for it, and none is needed.

## In-app popups

Triggered by MERGN campaigns in response to events, so nothing to call directly:

```js
await Mergn.performEvent("Collection Viewed", { title: "Beauty" });
```

The SDK renders the popup itself using the current Activity. If a popup does not
appear, check that a campaign is actually configured for that event name in your
MERGN dashboard.

## Transitive dependencies

The SDK's published POM declares no dependencies, so this package declares them
on the SDK's behalf: `androidx.room`, `androidx.work`, `androidx.core`,
`androidx.appcompat`, `kotlinx-coroutines-android` and `gson`, plus
`firebase-messaging` as `compileOnly` so it cannot conflict with your app's own
Firebase version.

If you see `NoClassDefFoundError` from inside `com.mergn.insights` at runtime,
that list has drifted — please report it.

## Troubleshooting

**`Duplicate class com.mergn.insights.*`** — you still have the old `.aar` in
`android/app/libs/`. See [MIGRATION.md](./MIGRATION.md) — and note that removing
the `.aar` alone is not sufficient.

**`Native module MergnModule tried to override ...`** — your old
`MergnModule.java` / `MergnPackage.java` are still in the app, so two modules
claim the same name. See [MIGRATION.md](./MIGRATION.md) steps 2 and 3.

**`MergnModule.<method> is unavailable`** — the native module did not load.
You are probably in Expo Go, which cannot load native code; use
`npx expo run:android` or an EAS build.

**Events send but nothing reaches the dashboard** — confirm `registerApi`
resolved *before* the events, and that your API key and package name are
provisioned in your MERGN account.

**An attribute does not update** — the SDK de-duplicates: setting the same value
again for one attribute name is intentionally a no-op. Use a changed value.
