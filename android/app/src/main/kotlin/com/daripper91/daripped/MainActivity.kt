package com.daripper91.daripped

import android.system.Os.setenv

import android.content.Intent
import android.os.Looper
import com.termux.x11.CmdEntryPoint
import androidx.annotation.NonNull
import androidx.annotation.Keep
import androidx.appcompat.app.AppCompatDelegate
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel


class MainActivity: FlutterActivity() {

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "android").setMethodCallHandler {
            // 注册通道并设置方法调用处理器
            call, result ->
            // 判断方法名
            when (call.method) {
                "launchSignal9Page" -> {
                    startActivity(Intent(this, Signal9Activity::class.java))
                    result.success(0)
                }
                "getNativeLibraryPath" -> {
                    result.success(getApplicationInfo().nativeLibraryDir)
                }
                "launchXServer" -> {
                    val tmpdir = call.argument<String>("tmpdir")
                    val xkb = call.argument<String>("xkb")
                    val xserverArgs = call.argument<List<String>>("xserverArgs")
                    if (tmpdir == null || xkb == null || xserverArgs == null) {
                        result.error("INVALID_ARGUMENTS", "tmpdir, xkb and xserverArgs are required", null)
                    } else {
                        try {
                            setenv("TMPDIR", tmpdir, true)
                            setenv("XKB_CONFIG_ROOT", xkb, true)
                            setenv("TERMUX_X11_DEBUG", "1", true)
                            setenv("TERMUX_X11_OVERRIDE_PACKAGE", packageName, true)
                            // CmdEntryPoint.main() posts the server start to a Handler bound to the
                            // calling thread's looper and then runs Looper.loop(). x11_flutter calls it
                            // on the UI thread, where that is a nested loop that never returns and
                            // Android 17 reports an ANR and kills the app. Give it its own looper thread.
                            Thread({
                                Looper.prepare()
                                CmdEntryPoint.main(xserverArgs.toTypedArray())
                            }, "x11-server").start()
                            result.success(0)
                        } catch (e: Exception) {
                            result.error("LAUNCH_XSERVER_FAILED", e.message, e.stackTraceToString())
                        }
                    }
                }
                "startStreaming" -> {
                    AudioStream.startStreaming(call.argument("path")!!)
                }
                "stopStreaming" -> {
                    AudioStream.stopStreaming()
                }
                else -> {
                    // 不支持的方法名
                    result.notImplemented()
                }
            }
        }
    }

}
