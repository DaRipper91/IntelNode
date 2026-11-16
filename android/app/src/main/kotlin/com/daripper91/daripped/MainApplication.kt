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
        // 1. Force touch mode, portrait orientation, and resolution scaling in SharedPreferences
        try {
            val sp = activity.getSharedPreferences("${activity.packageName}_preferences", Context.MODE_PRIVATE)
            sp.edit()
                .putBoolean("pointerCapture", false)
                .putBoolean("keepScreenOn", true)
                .putString("touchMode", "1")
                .putString("forceOrientation", "portrait")
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
                putExtra("forceOrientation", "portrait")
                putExtra("adjustResolution", "true")
                putExtra("displayStretch", "true")
            }
            activity.sendBroadcast(intent)
        } catch (_: Throwable) {}

        // 3. Explicitly lock activity window to portrait orientation
        try {
            activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
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
