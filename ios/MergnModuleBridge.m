#import <React/RCTBridgeModule.h>

// Registers the Swift MergnModule with React Native. The implementation lives in
// MergnModule.swift (mergn_ios ships a .swiftmodule only, so the SDK cannot be
// imported from Objective-C); this interface is what makes
// NativeModules.MergnModule resolve on the JS side.
@interface RCT_EXTERN_MODULE(MergnModule, NSObject)

RCT_EXTERN_METHOD(performAction:(NSString *)action
                       jsonData:(NSString *)jsonData
                       resolver:(RCTPromiseResolveBlock)resolve
                       rejecter:(RCTPromiseRejectBlock)reject)

@end
