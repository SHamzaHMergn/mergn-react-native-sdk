/**
 * MERGN SDK for React Native.
 *
 * The same API on Android and iOS: each method resolves with a status string
 * from the native SDK, or rejects with an Error. Requires a native rebuild
 * after install — Expo Go cannot load native modules.
 */
declare const Mergn: {
  /** Register your MERGN API key. Call this once, as early as app start. */
  registerApi(apiKey: string): Promise<string>;

  /** Record an event with optional properties. */
  performEvent(
    eventName: string,
    eventPropertiesMap?: Record<string, unknown>
  ): Promise<string>;

  /**
   * Set a user attribute. Note the SDK de-duplicates: sending the same value
   * again for the same name is intentionally a no-op.
   */
  setAttribute(attributeName: string, attributeValue: string): Promise<string>;

  /** Identify the current user, linking their anonymous activity to this id. */
  login(uniqueIdentifier: string): Promise<string>;

  /** Hand the FCM/APNs registration token to MERGN so it can send pushes. */
  setFirebaseToken(fcmTokenMergn: string): Promise<string>;

  /** Currently routes to the same native path as setFirebaseToken. */
  setAppContext(fcmTokenMergn: string): Promise<string>;
};

export default Mergn;

/** The raw native module. Undefined when the native build is missing. */
export const MergnModule: unknown;
