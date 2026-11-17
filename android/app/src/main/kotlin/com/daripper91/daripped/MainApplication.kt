package com.daripper91.daripped

import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.os.Bundle
import android.view.View
import com.google.android.material.color.DynamicColors
import io.flutter.app.FlutterApplication
import me.weishu.reflection.Reflection

class MainApplication : FlutterApplication() {

    private var lastMultiWindowMode: Boolean? = null

    override fun onCreate() {
        super.onCreate()
        DynamicColors.applyToActivitiesIfAvailable(this@MainApplication)

        val processName = runCatching { Application.getProcessName() }.getOrNull() ?: ""
        if (processName.endsWith(":x11")) {
            X11KeyboardReceiver.ensureServerStarted(this)
            registerActivityLifecycleCallbacks(object : ActivityLifecycleCallbacks {
                override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {
                    if (activity.javaClass.name == "com.termux.x11.MainActivity") {
                        applyX11Preferences(activity)
                        activity.window?.decorView?.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
                            if (activity.isInMultiWindowMode != lastMultiWindowMode) {
                                applyX11Preferences(activity)
                            }
                        }
                    }
                }
                override fun onActivityStarted(activity: Activity) {
                    if (activity.javaClass.name == "com.termux.x11.MainActivity") {
                        applyX11Preferences(activity)
                    }
                }
                override fun onActivityResumed(activity: Activity) {
                    if (activity.javaClass.name == "com.termux.x11.MainActivity") {
                        applyX11Preferences(activity)
                        activity.window?.decorView?.post {
                            applyX11Preferences(activity)
                            X11FloatingOverlay.attach(activity)
                        }
                    }
                }
                override fun onActivityPaused(activity: Activity) {}
                override fun onActivityStopped(activity: Activity) {}
                override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
                override fun onActivityDestroyed(activity: Activity) {}
            })
        }
    }

    private fun applyX11Preferences(activity: Activity) {
        val inMultiWindow = activity.isInMultiWindowMode
        lastMultiWindowMode = inMultiWindow
        val orientationPref = if (inMultiWindow) "auto" else "portrait"

        // 1. Force touch mode, dynamic orientation, and resolution scaling in SharedPreferences
        try {
            val sp = activity.getSharedPreferences("${activity.packageName}_preferences", Context.MODE_PRIVATE)
            sp.edit()
                .putBoolean("pointerCapture", false)
                .putBoolean("keepScreenOn", true)
                .putString("touchMode", "1")
                .putString("forceOrientation", orientationPref)
                .putBoolean("adjustResolution", true)
                .putBoolean("displayStretch", true)
                .apply()
        } catch (_: Throwable) {}

        // 2. Broadcast preference update to Termux:X11 preference receiver
        try {
            val intent = Intent("com.termux.x11.CHANGE_PREFERENCE").apply {
                setPackage(activity.packageName)
                putExtra("pointerCapture", "false")
                putExtra("keepScreenOn", "true")
                putExtra("touchMode", "1")
                putExtra("forceOrientation", orientationPref)
                putExtra("adjustResolution", "true")
                putExtra("displayStretch", "true")
            }
            activity.sendBroadcast(intent)
        } catch (_: Throwable) {}

        // 3. Update activity window orientation request:
        // In multi-window / split-screen, never lock orientation to portrait so the window can adapt freely.
        try {
            if (inMultiWindow) {
                if (activity.requestedOrientation != ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED) {
                    activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                }
            } else {
                if (activity.requestedOrientation != ActivityInfo.SCREEN_ORIENTATION_PORTRAIT) {
                    activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                }
            }
        } catch (_: Throwable) {}

        // 4. Immediately release pointer capture if requested by LorieView
        try {
            activity.window?.decorView?.releasePointerCapture()
            val lorieViewMethod = activity.javaClass.getMethod("getLorieView")
            val lorieView = lorieViewMethod.invoke(activity) as? View
            lorieView?.releasePointerCapture()
        } catch (_: Throwable) {}
    }

    override fun attachBaseContext(base: Context?) {
        super.attachBaseContext(base)
        Reflection.unseal(base)
    }
}
