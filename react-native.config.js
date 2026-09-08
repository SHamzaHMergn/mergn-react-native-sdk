// Tells React Native autolinking where the native code lives, so both platforms
// register themselves on install — no manual MainApplication or Podfile edits.
module.exports = {
  dependency: {
    platforms: {
      android: {
        sourceDir: 'android',
        packageImportPath: 'import com.mergn.reactnative.MergnPackage;',
        packageInstance: 'new MergnPackage()',
      },
      ios: {
        // Only the wrapper podspec is listed; it declares a dependency on
        // MergnSDK, which CocoaPods resolves from the podspec in this package
        // (see the podspec_repo note in README) or from the local path below.
        podspecPath: __dirname + '/mergn-react-native.podspec',
      },
    },
  },
};
