const {
  withAndroidManifest,
  withXcodeProject,
  withDangerousMod,
  AndroidConfig,
} = require("expo/config-plugins");
const fs = require("fs");
const path = require("path");

// Autolinking handles registering the native module on both platforms. This
// plugin covers what autolinking cannot:
//   - Android: the SDK's FirebaseMessagingService + the permissions it needs
//   - iOS:     CocoaPods/Xcode quirks that otherwise break the build
//   - iOS:     the optional rich-push NotificationService extension
//
// Everything here is idempotent, so re-running prebuild is safe.

const SERVICE = "com.mergn.insights.firebaseservices.FireBaseMessagingService";

const PERMISSIONS = [
  "android.permission.INTERNET",
  "android.permission.POST_NOTIFICATIONS",
  "android.permission.VIBRATE",
];

function withMergnAndroid(config) {
  return withAndroidManifest(config, (cfg) => {
    const manifest = cfg.modResults;

    for (const name of PERMISSIONS) {
      AndroidConfig.Manifest.ensurePermission(manifest, name);
    }

    const application = AndroidConfig.Manifest.getMainApplicationOrThrow(manifest);
    application.service = application.service ?? [];

    // The SDK's own messaging service must be declared for Mergn pushes to be
    // delivered on Android; there is no autolinking equivalent for manifest
    // entries.
    if (!application.service.some((s) => s.$?.["android:name"] === SERVICE)) {
      application.service.push({
        $: {
          "android:name": SERVICE,
          "android:exported": "true",
          "android:enabled": "true",
        },
        "intent-filter": [
          { action: [{ $: { "android:name": "com.google.firebase.MESSAGING_EVENT" } }] },
        ],
      });
    }

    return cfg;
  });
}

// Xcode 16/26 writes objectVersion 70+, which CocoaPods' Xcodeproj (<=1.16)
// cannot serialize — `pod install` dies with "Unable to find compatibility
// version string for object version `70`". Xcodeproj knows 63 and Xcode opens
// 63 fine, so pin it. Re-applied each prebuild because Xcode bumps it back
// whenever the project is opened in the IDE.
function withCocoaPodsCompatibleProject(config) {
  return withDangerousMod(config, [
    "ios",
    (cfg) => {
      const pbxproj = path.join(
        cfg.modRequest.platformProjectRoot,
        `${cfg.modRequest.projectName}.xcodeproj`,
        "project.pbxproj"
      );
      if (fs.existsSync(pbxproj)) {
        const before = fs.readFileSync(pbxproj, "utf8");
        const after = before.replace(/objectVersion = 7\d;/, "objectVersion = 63;");
        if (after !== before) fs.writeFileSync(pbxproj, after);
      }
      return cfg;
    },
  ]);
}

// @react-native-firebase/app adds a script phase that declares the app's BUILT
// Info.plist as an input but no outputs. Once any app extension has to be
// embedded, that produces a dependency cycle:
//   embed .appex -> needs app bundle -> needs Info.plist -> RNFB script -> ...
// and the build fails with "Cycle inside <app>". Clearing the input and marking
// the phase always-out-of-date breaks the cycle; the script still runs every
// build, which is what it wants anyway.
function withoutFirebaseScriptPhaseCycle(config) {
  return withDangerousMod(config, [
    "ios",
    (cfg) => {
      const pbxproj = path.join(
        cfg.modRequest.platformProjectRoot,
        `${cfg.modRequest.projectName}.xcodeproj`,
        "project.pbxproj"
      );
      if (!fs.existsSync(pbxproj)) return cfg;

      let contents = fs.readFileSync(pbxproj, "utf8");
      contents = contents.replace(
        /\/\* \[CP-User\] \[RNFB\] Core Configuration \*\/ = \{([\s\S]*?)\};/g,
        (match, body) => {
          let next = body.replace(/inputPaths = \([\s\S]*?\);/, "inputPaths = (\n\t\t\t);");
          if (!/alwaysOutOfDate/.test(next)) {
            next = next.replace(
              "isa = PBXShellScriptBuildPhase;",
              "isa = PBXShellScriptBuildPhase;\n\t\t\talwaysOutOfDate = 1;"
            );
          }
          return `/* [CP-User] [RNFB] Core Configuration */ = {${next}};`;
        }
      );
      fs.writeFileSync(pbxproj, contents);
      return cfg;
    },
  ]);
}

// The Mergn SDK is a separate pod (sdk/MergnSDK.podspec) rather than part of the
// autolinked wrapper, because a vendored framework declared on an autolinked pod
// does not produce link flags - the app builds with no -framework "mergn_ios"
// and then fails with "Unable to resolve module dependency: 'mergn_ios'".
//
// Autolinking cannot add a second pod, so inject it here. :path works because
// the framework is bundled in the package; it points at the DIRECTORY, and
// CocoaPods matches the podspec filename to the pod name - which is why
// MergnSDK.podspec sits alone in sdk/ with the framework.
function withMergnSdkPod(config) {
  return withDangerousMod(config, [
    "ios",
    (cfg) => {
      const podfile = path.join(cfg.modRequest.platformProjectRoot, "Podfile");
      if (!fs.existsSync(podfile)) return cfg;

      let contents = fs.readFileSync(podfile, "utf8");
      if (contents.includes("pod 'MergnSDK'")) return cfg;

      // Resolve from this plugin's own location so npm, yarn workspaces and
      // pnpm layouts all work.
      const packageRoot = path.join(__dirname, "..");
      const relative = path
        .relative(cfg.modRequest.platformProjectRoot, path.join(packageRoot, "sdk"))
        .split(path.sep)
        .join("/");

      const line = `  pod 'MergnSDK', :path => '${relative}'`;
      const anchor = "  use_expo_modules!";
      if (!contents.includes(anchor)) {
        throw new Error(
          "mergn-react-native: could not find 'use_expo_modules!' in the Podfile.\n" +
            "\nThis usually means the config plugin ran on a bare React Native " +
            "project, which does not use Expo's Podfile. Bare projects are " +
            "supported, but configure iOS by hand instead — see " +
            "https://github.com/mergn-code/App-SDK-Documentation/blob/main/MERGN%20React%20Native%20SDK.md#3-setup-bare-react-native\n" +
            "\nIf you meant to use the plugin, add this inside your app target:\n" +
            line + "\n"
        );
      }
      contents = contents.replace(anchor, `${anchor}\n${line}`);
      fs.writeFileSync(podfile, contents);
      return cfg;
    },
  ]);
}

// mergn_ios.xcframework is built for iOS 14, but Expo's Podfile template
// defaults to 13.4 — so `pod install` fails with "they required a higher minimum
// deployment target". Raise the floor here so the client does not have to know
// the SDK's minimum, and only ever raise it (never lower an app that already
// targets something newer).
const MIN_IOS = "14.0";

function withMinimumIosVersion(config) {
  return withDangerousMod(config, [
    "ios",
    (cfg) => {
      const file = path.join(
        cfg.modRequest.platformProjectRoot,
        "Podfile.properties.json"
      );
      let props = {};
      if (fs.existsSync(file)) {
        try {
          props = JSON.parse(fs.readFileSync(file, "utf8"));
        } catch {
          props = {};
        }
      }

      let changed = false;

      const current = parseFloat(props["ios.deploymentTarget"] ?? "0");
      if (!(current >= parseFloat(MIN_IOS))) {
        props["ios.deploymentTarget"] = MIN_IOS;
        changed = true;
      }

      // mergn_ios ships as a Swift .xcframework with only a .swiftmodule (no
      // ObjC headers). Without use_frameworks! the module is not importable and
      // the build fails with "Unable to resolve module dependency: 'mergn_ios'".
      // "static" is chosen over "dynamic" because it is also what Firebase needs
      // (its Swift pods cannot build against non-modular GoogleUtilities as
      // plain static libraries), and most RN apps using Mergn also use Firebase.
      if (!props["ios.useFrameworks"]) {
        props["ios.useFrameworks"] = "static";
        changed = true;
      }

      if (changed) {
        fs.writeFileSync(file, JSON.stringify(props, null, 2) + "\n");
      }
      return cfg;
    },
  ]);
}

module.exports = function withMergn(config, props = {}) {
  let next = withMergnAndroid(config);
  next = withMinimumIosVersion(next);
  next = withMergnSdkPod(next);
  next = withoutFirebaseScriptPhaseCycle(next);
  next = withCocoaPodsCompatibleProject(next);
  return next;
};
