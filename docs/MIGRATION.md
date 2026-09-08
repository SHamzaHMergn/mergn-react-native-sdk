# Migrating from a manual MERGN integration

If you wired MERGN in by hand — copying `MergnModule.java` into your app,
registering `MergnPackage()` in `MainApplication`, and dropping the `.aar` into
`android/app/libs/` — you **must remove those pieces** before installing this
package.

Read this page top to bottom before you start. The removal is not optional and
it is not all loud: one of the four steps fails your build immediately, and two
of them fail silently while the app still looks healthy.

- [Is removing the `.aar` enough?](#is-removing-the-aar-enough)
- [Android: removing the old integration, step by step](#android-removing-the-old-integration-step-by-step)
- [Android: installing the new package](#android-installing-the-new-package)
- [iOS: what to remove](#ios-what-to-remove)
- [JavaScript: update imports](#javascript-update-imports)
- [Verifying the migration worked](#verifying-the-migration-worked)
- [Rollback](#rollback)

---

## Is removing the `.aar` enough?

**No.** Removing the `.aar` fixes the *build failure*. Two further problems
remain, and neither announces itself:

| Step skipped | What happens | Do you notice? |
| --- | --- | --- |
| `.aar` left in `libs/` | `Duplicate class com.mergn.insights.*` — build fails | **Yes, immediately** |
| `MergnModule.java` / `MergnPackage.java` left in your app | Two native modules **both named `MergnModule`**. React Native registers one and warns; which one wins is not guaranteed | **No** — builds and runs |
| `packages.add(MergnPackage())` left in `MainApplication` | `MergnPackage` resolves to your *old* class, so this package's module is bypassed entirely | **No** |

Both old and new modules return the identical name from `getName()`:

```java
@Override
public String getName() {
    return "MergnModule";   // identical in com.android.test.MergnModule
}                            // and com.mergn.reactnative.MergnModule
```

`NativeModules.MergnModule` is resolved by that string, so with both classes
present your JS call may reach either one. The old one references SDK classes
that no longer come from an `.aar`, so you get a working-looking app with calls
landing in the wrong place.

Do all four steps below.

---

## Android: removing the old integration, step by step

### Step 1 — Find what you actually have

Run this from your project root. It prints every trace of the old integration:

```sh
echo "--- copied native sources ---"
find android/app/src/main/java -name 'Mergn*.java' -o -name 'Mergn*.kt'

echo "--- bundled SDK binaries ---"
find android -name '*.aar' | grep -i mergn

echo "--- gradle references ---"
grep -rn -i 'mergn\|libs/.*\.aar\|fileTree' android/app/build.gradle

echo "--- MainApplication registration ---"
grep -rn -i 'mergn' android/app/src/main/java --include='MainApplication.*'

echo "--- manifest service ---"
grep -n -i 'mergn' android/app/src/main/AndroidManifest.xml

echo "--- JS imports ---"
grep -rn 'MergnModule' --include='*.js' --include='*.jsx' --include='*.ts' --include='*.tsx' . \
  | grep -v node_modules
```

Everything it lists gets deleted. Keep the output — you will use it to confirm
you got all of it.

> **If `android/` is not committed to git** (a pure Expo CNG project where
> `npx expo prebuild` generates it), your changes live in `app.json`, a config
> plugin, or a `patch-package` patch instead. In that case delete the plugin or
> patch that injected MERGN, and run `npx expo prebuild --clean`. Steps 2–5 then
> apply to whatever your plugin was writing.

### Step 2 — Delete the copied native sources

```sh
rm -f android/app/src/main/java/<your/package/path>/MergnModule.java
rm -f android/app/src/main/java/<your/package/path>/MergnPackage.java
```

For example, if your package is `com.android.test`:

```sh
rm -f android/app/src/main/java/com/android/test/MergnModule.java
rm -f android/app/src/main/java/com/android/test/MergnPackage.java
```

If you translated them to Kotlin, delete the `.kt` files instead. If you also
added a custom `FirebaseMessagingService` subclass purely for MERGN, delete that
too — the SDK ships its own.

**This step is silent if you skip it.** Do not skip it.

### Step 3 — Un-register the package in `MainApplication`

`android/app/src/main/java/<your/package/path>/MainApplication.kt`:

```diff
  override fun getPackages(): List<ReactPackage> =
      PackageList(this).packages.apply {
-       add(MergnPackage())
      }
```

Or, if it's still Java:

```diff
  @Override
  protected List<ReactPackage> getPackages() {
    List<ReactPackage> packages = new PackageList(this).getPackages();
-   packages.add(new MergnPackage());
    return packages;
  }
```

Also delete the now-unused import if you had an explicit one:

```diff
- import com.android.test.MergnPackage;
```

Anything you added to `onCreate` for MERGN comes out as well:

```diff
  override fun onCreate() {
    super.onCreate()
-   MergnSDK.initialize(this)
  }
```

This package initializes the SDK for you on the first `registerApi` call.

**This step is also silent if you skip it.**

### Step 4 — Remove the bundled `.aar`

In `android/app/build.gradle`:

```diff
  dependencies {
-     implementation files('libs/MERGN_SDK_KOTLIN_REACT_NATIVE_5.2.4.aar')
  }
```

Some integrations used a `fileTree` instead — remove the MERGN part of it, or
the whole line if MERGN was the only thing in `libs/`:

```diff
- implementation fileTree(dir: 'libs', include: ['*.aar'])
```

Then delete the binaries:

```sh
rm -f android/app/libs/*mergn*.aar android/app/libs/*MERGN*.aar
rmdir android/app/libs 2>/dev/null   # only succeeds if now empty
```

If your old integration also declared the SDK's dependencies by hand (Room,
WorkManager, coroutines, gson…) *solely for MERGN*, remove those too — this
package declares them itself. Leave anything your own code uses.

**Skipping this step fails the build:**

```
Duplicate class com.mergn.insights.classes.EventManager found in modules
  jetified-MERGN_SDK_KOTLIN_REACT_NATIVE_5.2.4.aar and
  jetified-Mergn_sdk_android-5.2.4.aar
```

### Step 5 — Remove the hand-added manifest service

The config plugin declares MERGN's messaging service, so a hand-written
duplicate for the same class is a manifest-merger error. In
`android/app/src/main/AndroidManifest.xml`:

```diff
- <service
-     android:name="com.mergn.insights.firebaseservices.FireBaseMessagingService"
-     android:exported="false">
-     <intent-filter>
-         <action android:name="com.google.firebase.MESSAGING_EVENT" />
-     </intent-filter>
- </service>
```

Leave `INTERNET`, `POST_NOTIFICATIONS` and `VIBRATE` alone if they're there —
the plugin adds them idempotently, and duplicate `<uses-permission>` entries
merge cleanly.

### Step 6 — Confirm the old integration is gone

Re-run the Step 1 audit. Every section should now be empty except your JS
imports, which Step 8 handles:

```sh
find android/app/src/main/java -name 'Mergn*' ; \
find android -iname '*mergn*.aar' ; \
grep -rn -i mergn android/app/build.gradle android/app/src/main/AndroidManifest.xml ; \
grep -rn -i mergn android/app/src/main/java --include='MainApplication.*' ; \
echo "audit complete — no output above this line means clean"
```

---

## Android: installing the new package

### Step 7 — Install

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

That is the entire native setup. Autolinking registers the module; the config
plugin adds the manifest service and permissions; the package's own
`build.gradle` pulls the SDK from JitPack and declares its transitive
dependencies. You do **not** touch `MainApplication`, `settings.gradle`, or
`app/build.gradle` again.

See [ANDROID.md](./ANDROID.md) for Firebase/push setup and the Android 13+
runtime permission, which are unchanged from your old integration.

### Step 8 — Update your JavaScript

```diff
- import MergnModule from "../MergnModule";
+ import Mergn from "mergn-react-native";
```

**Method names, arguments and return values are identical**, so the call sites
do not change:

```js
await Mergn.registerApi(key);
await Mergn.performEvent("Collection Viewed", { title: "Beauty" });
await Mergn.setAttribute("Email", "user@example.com");
await Mergn.login("user@example.com");
await Mergn.setFirebaseToken(token);
await Mergn.setAppContext(token);
```

The action strings on the bridge (`register_api`, `perform_event`,
`add_attribute`, `login_mergn`, `firebase_token_mergn`, `mergn_app_context`) are
byte-identical to the old module's, so anything you built on top still lines up.

Delete your local `MergnModule.js`.

### Step 9 — Rebuild from scratch

Stale native artefacts survive an ordinary rebuild and will hide your work:

```sh
rm -rf android/app/build android/build android/.gradle
npx expo prebuild --platform android --clean
npx expo run:android
```

> `prebuild --clean` regenerates `android/`. If you hand-edited anything else in
> there that is *not* committed as a config plugin, it is lost — commit or note
> those changes first.

---

## iOS: what to remove

If you had a hand-rolled iOS integration:

1. Delete any hand-added bridge sources from `ios/<YourApp>/`:
   ```sh
   rm -f ios/<YourApp>/MergnModule.swift ios/<YourApp>/MergnModuleBridge.m
   ```
2. Remove a manual pod declaration from your `Podfile` — the config plugin
   injects it:
   ```diff
   - pod 'MergnSDK', :path => '...'
   ```
3. Delete a vendored framework from your project. Keeping it alongside the
   package's copy produces duplicate-symbol link errors:
   ```sh
   rm -rf ios/Frameworks/mergn_ios.xcframework
   ```
   Also remove it from the target's *Link Binary With Libraries* and *Embed
   Frameworks* phases in Xcode.
4. Rebuild clean:
   ```sh
   rm -rf ios/Pods ios/Podfile.lock ios/build
   npx expo prebuild --platform ios --clean
   npx expo run:ios
   ```

See [IOS.md](./IOS.md) for the full iOS setup.

---

## Verifying the migration worked

After `npx expo run:android`, watch the native log:

```sh
adb logcat -s MergnModule:D ReactNativeJS:V
```

Call each method once from your app. You should see exactly one line per call:

```
D MergnModule: Registered API key
D MergnModule: User Logged In
D MergnModule: Attribute Set: Email
D MergnModule: Event Sent: Collection Viewed
D MergnModule: Firebase Token Set
```

Then confirm the *new* class is the one running:

```sh
adb logcat -d | grep -i 'MergnModule\|mergn.reactnative'
```

Two warning signs:

- **`Native module MergnModule tried to override …`** in logcat — both modules
  are still registered. Step 2 or Step 3 was missed.
- **`MergnModule.<method> is unavailable`** thrown in JS — the native module did
  not load at all. You are either in Expo Go (which cannot load native code) or
  the build predates the install; re-run Step 9.

---

## Rollback

Nothing in the migration touches SDK storage. Same SDK version (Android 5.2.4,
iOS 19.0.0), same API key, same customer ids and attributes — identified users
stay identified across the upgrade, and back again.

To revert: `git revert` the migration commit, `npm uninstall
mergn-react-native`, then rebuild clean as in Step 9.

## If you cannot migrate yet

Stay on your manual integration — it keeps working. **Do not install this
package alongside it**; the duplicate-class failure has no workaround short of
removing one side.
