import { NativeModules, Platform } from "react-native";

export const MergnModule = NativeModules.MergnModule;

const call = (method, action, payload) =>
  MergnModule
    ? MergnModule.performAction(action, JSON.stringify(payload))
    : Promise.reject(
        new Error(
          `MergnModule.${method} is unavailable: the native module did not load on ${Platform.OS}. ` +
            `Rebuild the app after installing (npx expo prebuild && npx expo run:${Platform.OS}) — ` +
            `Expo Go cannot load native modules.`
        )
      );

export default {
  registerApi: (apiKey) => call("registerApi", "register_api", { apiKey }),

  performEvent: (eventName, eventPropertiesMap = {}) =>
    call("performEvent", "perform_event", { eventName, eventPropertiesMap }),

  setAttribute: (attributeName, attributeValue) =>
    call("setAttribute", "add_attribute", { attributeName, attributeValue }),

  login: (uniqueIdentifier) =>
    call("login", "login_mergn", { uniqueIdentifier }),

  setFirebaseToken: (fcmTokenMergn) =>
    call("setFirebaseToken", "firebase_token_mergn", { fcmTokenMergn }),

  // Currently routes to the same native path as setFirebaseToken.
  setAppContext: (fcmTokenMergn) =>
    call("setAppContext", "mergn_app_context", { fcmTokenMergn }),
};
