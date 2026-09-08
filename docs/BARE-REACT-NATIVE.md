# Setup without Expo (bare React Native)

This package works on bare React Native — Expo is **optional**. The native
module registers itself through React Native's own autolinking, which is core
RN, not an Expo feature.

What Expo gives you is automation. Its config plugin writes four pieces of
native configuration for you. Without Expo you write them once, by hand, and
they stay in your committed `android/` and `ios/` folders.

**Verified on:** React Native 0.76.5, bare (no Expo), `newArchEnabled=true` —
Android module compiles and registers in `PackageList.java`; iOS `pod install`
installs both `MergnSDK (19.0.0)` and `mergn-react-native (1.0.0)`.

- [What is automatic](#what-is-automatic)
- [What you do by hand](#what-you-do-by-hand)
- [Android](#android)
- [iOS](#ios)
- [Verify it worked](#verify-it-worked)
- [Troubleshooting](#troubleshooting)

---

## What is automatic

Nothing to do for any of these — `npm install` is enough:

| | How |
| --- | --- |
| Android module registration | Autolinking generates `PackageList.java` |
| MERGN Android SDK from JitPack | The package's own `build.gradle` |
| Android transitive dependencies | Declared by the package |
| iOS podspec discovery | Autolinking finds `mergn-react-native.podspec` |
| iOS bridge sources | Compiled by the pod |

You do **not** edit `MainApplication`, `settings.gradle`, or `app/build.gradle`.

## What you do by hand

| Step | Platform | Why it isn't automatic |
| --- | --- | --- |
| 1. Manifest service + permissions | Android | Autolinking cannot edit `AndroidManifest.xml` |
| 2. `pod 'MergnSDK'` | iOS | Podspecs cannot add a sibling local pod |
| 3. `use_frameworks!` | iOS | Must be set in your app's Podfile |
| 4. `platform :ios, '14.0'` | iOS | The SDK's floor is above RN's default |

Android is one file. iOS is three lines in the Podfile.

---

## Install

```sh
npm install mergn-react-native
```

There is no peer dependency on `expo`, so this installs cleanly with no
warnings on a bare project.

---

## Android

### Step 1 — `AndroidManifest.xml`

Edit `android/app/src/main/AndroidManifest.xml`.

Add the three permissions above `<application>`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.VIBRATE" />
```

Add MERGN's messaging service **inside** `<application>`:

```xml
<service
    android:name="com.mergn.insights.firebaseservices.FireBaseMessagingService"
    android:enabled="true"
    android:exported="true">
    <intent-filter>
        <action android:name="com.google.firebase.MESSAGING_EVENT" />
    </intent-filter>
</service>
```

Without the service, MERGN pushes are never delivered. Without
`POST_NOTIFICATIONS`, they are delivered but silently not displayed on
Android 13+.

That is the entire Android setup. Then:

```sh
npx react-native run-android
```

### Requirements

- `minSdkVersion` **24** or higher — the MERGN SDK's floor. In
  `android/build.gradle`:
  ```gradle
  ext { minSdkVersion = 24 }
  ```
- Java 17

### Overriding the SDK version

```gradle
ext { mergnSdkVersion = "5.2.5" }
```

---

## iOS

All three steps are in `ios/Podfile`.

### Step 2 — Deployment target (only on RN 0.72–0.75)

The MERGN iOS SDK is built for **iOS 14.0**, so your app's floor must be at
least that. Whether you need to change anything depends on your RN version:

| React Native | Its default floor | Action |
| --- | --- | --- |
| **0.76+** | 15.1 | **Nothing** — already above 14.0. Leave `min_ios_version_supported` alone |
| 0.74 – 0.75 | 13.4 | Raise it |
| 0.72 – 0.73 | 13.4 | Raise it |

On RN 0.72–0.75 only:

```diff
- platform :ios, min_ios_version_supported
+ platform :ios, '14.0'
```

> **Do not hardcode `'14.0'` on RN 0.76+.** It is *below* what React Native
> itself requires, and `pod install` fails with:
>
> ```
> [!] CocoaPods could not find compatible versions for pod "React-RuntimeHermes":
>     ... they required a higher minimum deployment target.
> ```
>
> Check your version's floor with:
> ```sh
> grep -A1 'def self.min_ios_version_supported' \
>   node_modules/react-native/scripts/cocoapods/helpers.rb
> ```

### Step 3 — `use_frameworks!`

`mergn_ios.xcframework` is a Swift-only framework: it ships a `.swiftmodule`
with no Objective-C headers, so it cannot be imported as a plain static
library. Without this you get *"Unable to resolve module dependency:
'mergn_ios'"*.

RN 0.76's template already has a conditional `use_frameworks!` driven by an
environment variable. Replace it with an unconditional static one:

```ruby
target 'YourApp' do
  use_frameworks! :linkage => :static
  # ...
end
```

> **Static, not dynamic.** Static is also what Firebase needs — its Swift pods
> cannot build against non-modular GoogleUtilities as plain static libraries —
> and most apps using MERGN also use Firebase.

### Step 4 — The MERGN SDK pod

The wrapper pod autolinks, but it depends on `MergnSDK`, which lives inside the
npm package. Point CocoaPods at it:

```ruby
target 'YourApp' do
  use_frameworks! :linkage => :static

  pod 'MergnSDK', :path => '../node_modules/mergn-react-native/sdk'

  # ...
end
```

> The path is relative to your **Podfile**, not the project root. Adjust for
> monorepos: in a Yarn/pnpm workspace where `node_modules` is hoisted, it may be
> `'../../node_modules/mergn-react-native/sdk'`. If the path is wrong, CocoaPods
> reports `No podspec found for 'MergnSDK'`.

### Then install and run

```sh
cd ios && pod install && cd ..
npx react-native run-ios
```

### A complete Podfile

For reference, the three changes together:

```ruby
require Pod::Executable.execute_command('node', ['-p',
  'require.resolve("react-native/scripts/react_native_pods.rb", {paths: [process.argv[1]]})',
  __dir__]).strip

platform :ios, min_ios_version_supported   # step 2: see the table above
prepare_react_native_project!

target 'YourApp' do
  use_frameworks! :linkage => :static      # step 3

  pod 'MergnSDK', :path => '../node_modules/mergn-react-native/sdk'  # step 4

  config = use_native_modules!

  use_react_native!(
    :path => config[:reactNativePath],
    :app_path => "#{Pod::Config.instance.installation_root}/.."
  )

  post_install do |installer|
    react_native_post_install(installer, config[:reactNativePath])
  end
end
```

### Rich push images (optional)

For images in notifications you need a Notification Service Extension. The
package ships one at
`node_modules/mergn-react-native/ios/NotificationService/`. Add it in Xcode:

1. **File → New → Target → Notification Service Extension**
2. Set its **deployment target to 14.0** — it must not exceed your app's, or the
   app will not install
3. Replace the generated `NotificationService.swift` with the package's copy
4. Confirm the file is in the target's **Build Phases → Compile Sources**

MERGN sends `mutable-content: 1` and an `image` key in the payload, which the
extension reads.

> Service extensions are **not invoked on the iOS Simulator**. Rich images can
> only be verified on a physical device.

---

## Verify it worked

```js
import Mergn from 'mergn-react-native';

await Mergn.registerApi('YOUR_API_KEY');
await Mergn.login('user@example.com');
await Mergn.setAttribute('Email', 'user@example.com');
await Mergn.performEvent('Collection Viewed', { title: 'Beauty' });
```

**Android:**
```sh
adb logcat -s MergnModule:D
```
```
D MergnModule: Registered API key
D MergnModule: User Logged In
D MergnModule: Attribute Set: Email
D MergnModule: Event Sent: Collection Viewed
```

**iOS** — in Xcode's console, or `npx react-native log-ios`:
```
[MergnModule] Registered API key
[MergnModule] User Logged In: user@example.com (customerId now 'user@example.com')
```

To confirm the module linked at all:

```js
import { NativeModules } from 'react-native';
console.log('linked:', !!NativeModules.MergnModule);
```

---

## Troubleshooting

**`could not find 'use_expo_modules!' in the Podfile`** — you ran the Expo
config plugin on a bare project. Don't; follow steps 2–4 instead. The error
message includes the pod line you need.

**`No podspec found for 'MergnSDK'`** — the `:path` in step 4 is wrong. Check it
resolves:
```sh
ls node_modules/mergn-react-native/sdk/MergnSDK.podspec
```
and make the path relative to `ios/Podfile`.

**`Unable to resolve module dependency: 'mergn_ios'`** — step 3 missing. The
Swift-only framework needs `use_frameworks!`.

**`they required a higher minimum deployment target`** — a deployment-target
mismatch, in one of two directions:

- naming a version *below* React Native's own floor (e.g. `'14.0'` on RN 0.76,
  which needs 15.1) — the pod named in the error is usually a React pod such as
  `React-RuntimeHermes`. Restore `min_ios_version_supported`.
- being below the MERGN SDK's 14.0 on RN 0.72–0.75 — the error names `MergnSDK`.
  Raise it to `'14.0'`.

See the table in [step 2](#step-2--deployment-target-only-on-rn-072075).

**`MergnModule.<method> is unavailable`** — the native module did not load.
Rebuild; `npm install` alone does not link native code. On iOS, re-run
`pod install`.

**`Duplicate class com.mergn.insights.*`** — an older manual MERGN integration
is still present. See [MIGRATION.md](./MIGRATION.md).

**Manifest merger failure on the service** — it is declared twice. Keep only
one.

---

## New Architecture

Old and new architectures are both supported. The module uses the classic bridge
API, which the New Architecture runs through its interop layer.

Verified on RN 0.76.5 with `newArchEnabled=true`: the module compiles, the app
builds, and `MergnPackage()` appears in the generated `PackageList.java`.

> Interop is a transitional layer that React Native maintains for classic
> modules. It works today and there is nothing for you to configure.

## Support matrix

| | Supported |
| --- | --- |
| React Native | 0.72+ (verified on 0.74.5 and 0.76.5) |
| Expo | SDK 50+ — optional |
| Architecture | Old and new (new via interop) |
| Android | API 24+ |
| iOS | 14.0+, device and simulator |
| Expo Go | **No** — cannot load native modules |
| macOS / tvOS / visionOS / Web | **No** |
