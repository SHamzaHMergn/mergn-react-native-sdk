#!/usr/bin/env node
// Runs on `npm pack`/`npm publish` (prepack). Fails the publish if anything a
// client needs is missing — most importantly the native binaries, which are the
// easiest thing to lose to a stray .npmignore or a bad `files` entry.
const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");
const required = [
  "src/index.js",
  "src/index.d.ts",
  "app.plugin.js",
  "plugin/index.js",
  "react-native.config.js",
  "mergn-react-native.podspec",
  "ios/MergnModule.swift",
  "ios/MergnNotificationHandler.swift",
  "sdk/MergnSDK.podspec",
  "ios/MergnModuleBridge.m",
  "android/build.gradle",
  "android/src/main/java/com/mergn/reactnative/MergnModule.java",
  "android/src/main/java/com/mergn/reactnative/MergnPackage.java",
  "README.md",
];

const missing = required.filter((rel) => !fs.existsSync(path.join(root, rel)));

// Android resolves from JitPack, so no .aar should ship. iOS IS bundled (see
// the podspec) because a vendored framework fetched at install time does not
// reliably link.
if (fs.existsSync(path.join(root, "android", "libs"))) {
  missing.push("android/libs should not ship - the Android SDK resolves from JitPack");
}

// Both xcframework slices are required: a device-only framework fails to link
// for the simulator, and vice versa.
for (const slice of ["ios-arm64", "ios-arm64_x86_64-simulator"]) {
  const bin = path.join(root, "sdk", "mergn_ios.xcframework", slice,
                        "mergn_ios.framework", "mergn_ios");
  if (!fs.existsSync(bin)) missing.push(`xcframework slice missing: ${slice}`);
}

if (missing.length) {
  console.error("\nmergn-react-native: package is incomplete, refusing to publish:");
  for (const m of missing) console.error(`  missing  ${m}`);
  console.error(
    "\nFix the above before publishing: a client's native build depends on " +
      "these files or coordinates being correct.\n"
  );
  process.exit(1);
}

// Both xcframework slices are required: device-only fails to link for the
// simulator, and vice versa.
console.log(
  "mergn-react-native: package verified " +
    "(Android SDK from JitPack, iOS xcframework bundled)"
);
