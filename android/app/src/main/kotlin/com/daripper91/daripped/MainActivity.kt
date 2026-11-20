package com.daripper91.daripped

import android.system.Os.setenv

import android.content.Intent
import android.os.Looper
import android.util.Log
import androidx.annotation.NonNull
import androidx.annotation.Keep
import androidx.appcompat.app.AppCompatDelegate
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel


class MainActivity: FlutterActivity() {

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "android")
        channel.setMethodCallHandler {
            // 注册通道并设置方法调用处理器
            call, result ->
            // 判断方法名
            when (call.method) {
                "startContainerService" -> {
                    ContainerSessionService.start(this)
                    result.success(0)
                }
                "stopContainerService" -> {
                    ContainerSessionService.stop(this)
                    result.success(0)
                }
                "launchSignal9Page" -> {
                    startActivity(Intent(this, Signal9Activity::class.java))
                    result.success(0)
                }
                "getNativeLibraryPath" -> {
                    result.success(getApplicationInfo().nativeLibraryDir)
                }
                "launchXServer" -> {
                    // Keep process immune from Android CachedAppOptimizer cgroup freeze
                    ContainerSessionService.start(this)
                    val tmpdir = call.argument<String>("tmpdir")
                    val xkb = call.argument<String>("xkb")
                    val xserverArgs = call.argument<List<String>>("xserverArgs")
                    if (tmpdir == null || xkb == null || xserverArgs == null) {
                        result.error("INVALID_ARGUMENTS", "tmpdir, xkb and xserverArgs are required", null)
                    } else {
                        try {
                            setenv("TMPDIR", tmpdir, true)
                            setenv("XKB_CONFIG_ROOT", xkb, true)
                            if (BuildConfig.DEBUG) {
                                setenv("TERMUX_X11_DEBUG", "1", true)
                            }
                            setenv("TERMUX_X11_OVERRIDE_PACKAGE", packageName, true)
                            // CmdEntryPoint.main() posts the server start to a Handler bound to the
                            // calling thread's looper and then runs Looper.loop(). x11_flutter calls it
                            // on the UI thread, where that is a nested loop that never returns and
                            // Android 17 reports an ANR and kills the app. Give it its own looper thread.
                            Thread({
                                try {
                                    Looper.prepare()
                                    // Reflection: the plugin's classes are not on this module's compile classpath.
                                    Class.forName("com.termux.x11.CmdEntryPoint")
                                        .getMethod("main", Array<String>::class.java)
                                        .invoke(null, xserverArgs.toTypedArray())
                                } catch (t: Throwable) {
                                    // An uncaught exception on this thread would kill the app, and the
                                    // caller already got result.success; report it back to Dart instead.
                                    val cause = t.cause ?: t
                                    Log.e("IntelNode", "X server entry point failed", cause)
                                    runOnUiThread { channel.invokeMethod("xServerLaunchFailed", cause.toString()) }
                                }
                            }, "x11-server").start()
                            result.success(0)
                        } catch (e: Exception) {
                            result.error("LAUNCH_XSERVER_FAILED", e.message, e.stackTraceToString())
                        }
                    }
                }
                "startStreaming" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("INVALID_ARGUMENTS", "path is required", null)
                    } else if (AudioStream.startStreaming(path)) {
                        result.success(null)
                    } else {
                        result.error("STREAMING_UNAVAILABLE", "Microphone streaming could not be started", null)
                    }
                }
                "stopStreaming" -> {
                    AudioStream.stopStreaming()
                    result.success(null)
                }
                else -> {
                    // 不支持的方法名
                    result.notImplemented()
                }
            }
        }
    }

}
