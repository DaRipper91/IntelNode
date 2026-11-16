package com.daripper91.daripped

import android.app.Activity
import android.app.Application
import android.content.Context
import android.os.Bundle
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
                override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
                override fun onActivityStarted(activity: Activity) {}
                override fun onActivityResumed(activity: Activity) {
                    if (activity.javaClass.name == "com.termux.x11.MainActivity") {
                        activity.window?.decorView?.post {
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

    override fun attachBaseContext(base: Context?) {
        super.attachBaseContext(base)
        Reflection.unseal(base)
    }
}
