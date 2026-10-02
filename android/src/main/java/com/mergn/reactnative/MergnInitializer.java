package com.mergn.reactnative;

import android.app.Application;
import android.content.Context;

import androidx.annotation.NonNull;
import androidx.startup.Initializer;
import androidx.work.WorkManagerInitializer;

import com.mergn.insights.classes.MergnSDK;

import java.util.Collections;
import java.util.List;

/**
 * Starts the MERGN SDK when the app process starts, via AndroidX App Startup,
 * so the client never edits MainApplication.
 *
 * MergnSDK.initialize() registers the SDK's activity lifecycle listener. If it
 * only ran inside registerApi() (~2s after launch, once JS is up), MainActivity
 * would already be started and resumed, so the SDK would miss the cold-start
 * launch, a notification tap that opened the app, and keep its foreground /
 * background counter off by one for the whole session. Running here — before
 * Application.onCreate() — catches all of it. No API key is needed; JS still
 * calls registerApi() for that, and the SDK's own initialize() ignores repeat
 * calls, so MergnModule calling it again is harmless.
 *
 * Opt out (e.g. to initialize yourself) by removing the meta-data entry in the
 * app manifest with tools:node="remove".
 */
public class MergnInitializer implements Initializer<Void> {
    @NonNull
    @Override
    public Void create(@NonNull Context context) {
        MergnSDK.initialize((Application) context.getApplicationContext());
        return null;
    }

    // initialize() enqueues the SDK's periodic WorkManager job, so WorkManager
    // must be initialized first or that job is never scheduled.
    @NonNull
    @Override
    public List<Class<? extends Initializer<?>>> dependencies() {
        return Collections.singletonList(WorkManagerInitializer.class);
    }
}
