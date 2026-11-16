package com.daripper91.daripped

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.View
import android.view.WindowInsets
import android.view.inputmethod.InputMethodManager
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket

class X11KeyboardReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (action == ACTION_KEYBOARD) {
            val state = intent.getStringExtra(EXTRA_STATE) ?: "show"
            Log.d(TAG, "Received ACTION_KEYBOARD: state=$state")
            ensureServerStarted(context.applicationContext)
            applyKeyboardState(context.applicationContext, state)
        }
    }

    companion object {
        const val TAG = "X11KeyboardReceiver"
        const val ACTION_KEYBOARD = "com.daripper91.daripped.ACTION_KEYBOARD"
        const val EXTRA_STATE = "state"
        private const val PORT = 4720
        private const val DEBOUNCE_HIDE_MS = 200L

        private val mainHandler = Handler(Looper.getMainLooper())
        private var hideRunnable: Runnable? = null

        @Volatile
        private var serverRunning = false
        private var serverThread: Thread? = null

        @Synchronized
        fun ensureServerStarted(context: Context) {
            if (serverRunning) return
            serverRunning = true
            serverThread = Thread({
                var serverSocket: ServerSocket? = null
                try {
                    serverSocket = ServerSocket(PORT, 10, InetAddress.getByName("127.0.0.1"))
                    serverSocket.reuseAddress = true
                    Log.i(TAG, "IntelNode IME socket bound to 127.0.0.1:$PORT")
                    while (serverRunning && !serverSocket.isClosed) {
                        try {
                            val client = serverSocket.accept()
                            handleClientSocket(context, client)
                        } catch (e: Exception) {
                            if (!serverRunning) break
                            Log.w(TAG, "Socket accept error: ${e.message}")
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "TCP socket server failed on port $PORT: ${e.message}", e)
                } finally {
                    try {
                        serverSocket?.close()
                    } catch (_: Exception) {}
                    serverRunning = false
                }
            }, "intelnode-ime-server").apply {
                isDaemon = true
                start()
            }
        }

        private fun handleClientSocket(context: Context, socket: Socket) {
            Thread {
                try {
                    socket.use { s ->
                        val reader = BufferedReader(InputStreamReader(s.getInputStream()))
                        val line = reader.readLine()?.trim()?.lowercase()
                        if (line != null) {
                            val state = when (line) {
                                "show", "1", "open", "in" -> "show"
                                "hide", "0", "close", "out" -> "hide"
                                "toggle" -> "toggle"
                                else -> line
                            }
                            applyKeyboardState(context, state)
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Client socket error: ${e.message}")
                }
            }.start()
        }

        fun applyKeyboardState(context: Context, state: String) {
            mainHandler.post {
                when (state.lowercase()) {
                    "show" -> {
                        hideRunnable?.let {
                            mainHandler.removeCallbacks(it)
                            hideRunnable = null
                        }
                        performShowKeyboard(context)
                    }
                    "hide" -> {
                        hideRunnable?.let { mainHandler.removeCallbacks(it) }
                        val runnable = Runnable {
                            performHideKeyboard(context)
                            hideRunnable = null
                        }
                        hideRunnable = runnable
                        mainHandler.postDelayed(runnable, DEBOUNCE_HIDE_MS)
                    }
                    "toggle" -> {
                        hideRunnable?.let {
                            mainHandler.removeCallbacks(it)
                            hideRunnable = null
                        }
                        performToggleKeyboard(context)
                    }
                }
            }
        }

        fun getTermuxMainActivity(): Activity? {
            return try {
                val clazz = Class.forName("com.termux.x11.MainActivity")
                val method = clazz.getMethod("getInstance")
                method.invoke(null) as? Activity
            } catch (t: Throwable) {
                null
            }
        }

        fun getLorieView(activity: Activity): View? {
            return try {
                val method = activity.javaClass.getMethod("getLorieView")
                method.invoke(activity) as? View
            } catch (t: Throwable) {
                null
            }
        }

        fun performShowKeyboard(context: Context) {
            val activity = getTermuxMainActivity() ?: return
            val lorieView = getLorieView(activity)
            if (lorieView != null) {
                lorieView.isFocusable = true
                lorieView.isFocusableInTouchMode = true
                lorieView.requestFocus()
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                activity.window?.insetsController?.show(WindowInsets.Type.ime())
            }

            val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
            val shown = if (lorieView != null && imm != null) {
                imm.showSoftInput(lorieView, InputMethodManager.SHOW_IMPLICIT)
            } else false

            if (!shown && imm != null) {
                try {
                    imm.toggleSoftInput(InputMethodManager.SHOW_FORCED, 0)
                } catch (e: Exception) {
                    Log.w(TAG, "toggleSoftInput fallback failed: ${e.message}")
                }
            }
        }

        fun performHideKeyboard(context: Context) {
            val activity = getTermuxMainActivity() ?: return
            val lorieView = getLorieView(activity)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                activity.window?.insetsController?.hide(WindowInsets.Type.ime())
            }

            val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
            val token = lorieView?.windowToken ?: activity.window?.decorView?.rootView?.windowToken
            if (imm != null && token != null) {
                imm.hideSoftInputFromWindow(token, 0)
            }
        }

        fun performToggleKeyboard(context: Context) {
            try {
                val clazz = Class.forName("com.termux.x11.MainActivity")
                val method = clazz.getMethod("toggleKeyboardVisibility", Context::class.java)
                method.invoke(null, context)
            } catch (t: Throwable) {
                val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
                imm?.toggleSoftInput(InputMethodManager.SHOW_FORCED, 0)
            }
        }
    }
}
