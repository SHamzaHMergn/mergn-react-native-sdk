package com.mergn.reactnative;

import android.app.Activity;
import android.app.Application;
import android.content.Context;
import android.util.Log;

import com.facebook.react.bridge.Promise;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactContextBaseJavaModule;
import com.facebook.react.bridge.ReactMethod;
import com.mergn.insights.classes.AttributeManager;
import com.mergn.insights.classes.EventManager;
import com.mergn.insights.classes.MergnContext;
import com.mergn.insights.classes.MergnSDK;

import org.json.JSONObject;

import java.util.HashMap;
import java.util.Iterator;
import java.util.Map;

public class MergnModule extends ReactContextBaseJavaModule {
    private static final String TAG = "MergnModule";
    private static final String ACTION_REGISTER_API = "register_api";
    private static final String ACTION_PERFORM_EVENT = "perform_event";
    private static final String ACTION_SET_ATTRIBUTE = "add_attribute";
    private static final String ACTION_LOGIN = "login_mergn";
    private static final String ACTION_FIREBASE_TOKEN_MERGN = "firebase_token_mergn";
    private static final String MERGN_APP_CONTEXT = "mergn_app_context";

    // MergnSDK.initialize registers activity lifecycle callbacks, so calling it on
    // every register_api would stack duplicate listeners.
    private static boolean sdkInitialized = false;

    private final EventManager eventManager = new EventManager();
    private final AttributeManager attributeManager = new AttributeManager();

    public MergnModule(ReactApplicationContext reactContext) {
        super(reactContext);
    }

    @Override
    public String getName() {
        return "MergnModule";
    }

    @ReactMethod
    public void performAction(String action, String jsonData, Promise promise) {
        try {
            JSONObject options = new JSONObject(jsonData);

            ReactApplicationContext appCtx = getReactApplicationContext();
            Activity activity = getCurrentActivity();
            Log.d(TAG, "Received Action: " + action
                    + " | activity=" + (activity == null ? "NULL" : "present"));
            // The SDK renders in-app popups, which need an Activity. Fall back to the
            // application context so backgrounded calls still record instead of failing.
            Context uiCtx = activity != null ? activity : appCtx;

            switch (action) {
                case ACTION_REGISTER_API: {
                    String apiKey = options.getString("apiKey");
                    if (!sdkInitialized) {
                        MergnSDK.initialize((Application) appCtx.getApplicationContext());
                        sdkInitialized = true;
                    }
                    if (activity != null) {
                        MergnContext.context = activity;
                    }
                    eventManager.registerApiKey(apiKey, appCtx);
                    Log.d(TAG, "Registered API key");
                    promise.resolve("API Key Registered");
                    break;
                }

                case ACTION_PERFORM_EVENT: {
                    String eventName = options.getString("eventName");
                    Map<String, String> eventPropertiesMap = new HashMap<>();
                    JSONObject rawProperties = options.optJSONObject("eventPropertiesMap");
                    if (rawProperties != null) {
                        Iterator<String> keys = rawProperties.keys();
                        while (keys.hasNext()) {
                            String key = keys.next();
                            eventPropertiesMap.put(key, String.valueOf(rawProperties.get(key)));
                        }
                    }
                    // Argument order is load-bearing. The SDK declares:
                    //   sendEvent(eventName, properties, activityContext, clientAppContext)
                    // so the ACTIVITY must be 3rd and the app context 4th.
                    //
                    // EventManager builds the in-app popup with
                    //   var dialogContext = activityContext
                    // and only swaps to the app context when Settings.canDrawOverlays()
                    // is true — which never happens in production, since the SDK does not
                    // request SYSTEM_ALERT_WINDOW and users must enable it by hand.
                    // So activityContext IS the popup's context. Passing an Application
                    // context there makes AlertDialog.show() throw BadTokenException,
                    // which CampaignView.show() swallows in an empty catch — the popup
                    // silently never appears while the SDK still logs " In App Showed"
                    // and sets IS_IN_APP_SHOWN = true.
                    eventManager.sendEvent(eventName, eventPropertiesMap, uiCtx, appCtx);
                    Log.d(TAG, "Event Sent: " + eventName);
                    promise.resolve("Event Performed");
                    break;
                }

                case ACTION_SET_ATTRIBUTE: {
                    String attributeName = options.getString("attributeName");
                    String attributeValue = options.getString("attributeValue");
                    attributeManager.sendAttribute(appCtx, attributeName, attributeValue);
                    Log.d(TAG, "Attribute Set: " + attributeName);
                    promise.resolve("Attribute Set");
                    break;
                }

                case ACTION_LOGIN: {
                    String uniqueIdentifier = options.getString("uniqueIdentifier");
                    eventManager.login(uniqueIdentifier, uiCtx);
                    Log.d(TAG, "User Logged In");
                    promise.resolve("User Logged In");
                    break;
                }

                case ACTION_FIREBASE_TOKEN_MERGN: {
                    String fcmTokenMergn = options.getString("fcmTokenMergn");
                    eventManager.firebaseToken(fcmTokenMergn, uiCtx);
                    Log.d(TAG, "Firebase Token Set");
                    promise.resolve("Firebase Token Set");
                    break;
                }

                // TODO: currently identical to firebase_token_mergn. Needs a product
                // decision on what app-context registration should actually do.
                case MERGN_APP_CONTEXT: {
                    String contextToken = options.getString("fcmTokenMergn");
                    eventManager.firebaseToken(contextToken, uiCtx);
                    Log.d(TAG, "Firebase Token in App Context Set");
                    promise.resolve("Firebase Token in App Context Set");
                    break;
                }

                default:
                    promise.reject("UNSUPPORTED_ACTION", "Action " + action + " is not supported.");
                    break;
            }
        } catch (Exception e) {
            Log.e(TAG, "performAction failed for action " + action, e);
            promise.reject("MERGN_ERROR", e);
        }
    }
}
