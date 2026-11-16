package com.daripper91.daripped

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.util.DisplayMetrics
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.inputmethod.InputMethodManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView

@SuppressLint("ClickableViewAccessibility")
class X11FloatingOverlay private constructor(private val activity: Activity) {

    private val rootGroup: ViewGroup? = activity.findViewById(android.R.id.content)
        ?: (activity.window.decorView as? ViewGroup)

    private val container = FrameLayout(activity)
    private val collapsedPill = LinearLayout(activity)
    private val expandedBar = LinearLayout(activity)

    private var initialX = 0f
    private var initialY = 0f
    private var touchStartX = 0f
    private var touchStartY = 0f
    private var isDragging = false
    private val clickThresholdDp = 10f

    init {
        setupViews()
    }

    private fun dpToPx(dp: Float): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            dp,
            activity.resources.displayMetrics
        ).toInt()
    }

    private fun createRoundedBackground(bgColor: Int, radiusDp: Float, strokeColor: Int = 0x33FFFFFF): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dpToPx(radiusDp).toFloat()
            setColor(bgColor)
            setStroke(dpToPx(1f), strokeColor)
        }
    }

    private fun setupViews() {
        if (rootGroup == null) return

        val pad8 = dpToPx(8f)
        val pad12 = dpToPx(12f)
        val pad16 = dpToPx(16f)

        // 1. Root Container
        container.elevation = dpToPx(12f).toFloat()
        val params = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT
        )
        params.gravity = Gravity.TOP or Gravity.START
        container.layoutParams = params

        // Default initial position (top right edge)
        val dm = DisplayMetrics()
        activity.windowManager.defaultDisplay.getMetrics(dm)
        container.x = (dm.widthPixels - dpToPx(80f)).toFloat()
        container.y = dpToPx(120f).toFloat()

        // 2. Collapsed Pill (Compact draggable floating tab)
        collapsedPill.orientation = LinearLayout.HORIZONTAL
        collapsedPill.gravity = Gravity.CENTER
        collapsedPill.background = createRoundedBackground(Color.parseColor("#E61E1E2E"), 24f)
        collapsedPill.setPadding(pad12, pad8, pad12, pad8)

        val kbdIcon = TextView(activity).apply {
            text = "⌨"
            textSize = 20f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setPadding(0, 0, pad8, 0)
        }

        val expandDots = TextView(activity).apply {
            text = "⋯"
            textSize = 18f
            setTextColor(Color.parseColor("#BBBBCC"))
            gravity = Gravity.CENTER
        }

        collapsedPill.addView(kbdIcon)
        collapsedPill.addView(expandDots)

        // 3. Expanded Action Bar
        expandedBar.orientation = LinearLayout.HORIZONTAL
        expandedBar.gravity = Gravity.CENTER_VERTICAL
        expandedBar.background = createRoundedBackground(Color.parseColor("#F2181825"), 28f)
        expandedBar.setPadding(pad12, pad8, pad12, pad8)
        expandedBar.visibility = View.GONE

        fun createActionButton(label: String, tooltip: String, onClick: () -> Unit): TextView {
            return TextView(activity).apply {
                text = label
                textSize = 15f
                typeface = Typeface.DEFAULT_BOLD
                setTextColor(Color.WHITE)
                gravity = Gravity.CENTER
                setPadding(pad12, pad8, pad12, pad8)
                background = createRoundedBackground(Color.parseColor("#2A2A3C"), 16f, 0x22FFFFFF)
                val btnParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                ).apply {
                    setMargins(dpToPx(4f), 0, dpToPx(4f), 0)
                }
                layoutParams = btnParams
                setOnClickListener { onClick() }
            }
        }

        // Action Buttons
        val kbdBtn = createActionButton("⌨ Kbd", "Toggle Keyboard") {
            toggleKeyboard()
        }

        val prefsBtn = createActionButton("⚙ Settings", "X11 Preferences") {
            openPreferences()
        }

        val hubBtn = createActionButton("📱 Hub", "Return to Container Hub") {
            returnToHub()
        }

        val scaleView = createActionButton("📐 150%", "Cycle Display Scale (100%-200%)") {
            toggleScaleFactor()
        }
        scaleBtn = scaleView

        val hideBtn = createActionButton("✕", "Collapse Tab") {
            collapseToPill()
        }

        expandedBar.addView(kbdBtn)
        expandedBar.addView(prefsBtn)
        expandedBar.addView(scaleView)
        expandedBar.addView(hubBtn)
        expandedBar.addView(hideBtn)

        container.addView(collapsedPill)
        container.addView(expandedBar)

        // Drag & Click handler on Collapsed Pill
        collapsedPill.setOnTouchListener { v, event ->
            handleDragTouch(v, event, onClick = {
                // Quick tap on collapsed pill toggles soft keyboard directly!
                toggleKeyboard()
            }, onLongClick = {
                expandActionBar()
            })
        }

        // Allow clicking the dots explicitly to expand
        expandDots.setOnClickListener {
            expandActionBar()
        }

        rootGroup.addView(container)
    }

    private fun handleDragTouch(
        view: View,
        event: MotionEvent,
        onClick: () -> Unit,
        onLongClick: () -> Unit
    ): Boolean {
        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                initialX = container.x
                initialY = container.y
                touchStartX = event.rawX
                touchStartY = event.rawY
                isDragging = false
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                val dx = event.rawX - touchStartX
                val dy = event.rawY - touchStartY
                val threshold = dpToPx(clickThresholdDp)
                if (!isDragging && (Math.abs(dx) > threshold || Math.abs(dy) > threshold)) {
                    isDragging = true
                }
                if (isDragging) {
                    val rootW = rootGroup?.width ?: 1080
                    val rootH = rootGroup?.height ?: 1920
                    val newX = (initialX + dx).coerceIn(0f, (rootW - container.width).toFloat().coerceAtLeast(0f))
                    val newY = (initialY + dy).coerceIn(0f, (rootH - container.height).toFloat().coerceAtLeast(0f))
                    container.x = newX
                    container.y = newY
                }
                return true
            }
            MotionEvent.ACTION_UP -> {
                if (!isDragging) {
                    // Check if tap was on the expand icon side vs the keyboard icon
                    val localX = event.x
                    if (localX > view.width * 0.55f) {
                        onLongClick()
                    } else {
                        onClick()
                    }
                }
                return true
            }
        }
        return false
    }

    private fun expandActionBar() {
        collapsedPill.visibility = View.GONE
        expandedBar.visibility = View.VISIBLE
        // Clamp bounds after expansion
        container.post {
            val rootW = rootGroup?.width ?: 1080
            if (container.x + container.width > rootW) {
                container.x = (rootW - container.width - dpToPx(16f)).toFloat().coerceAtLeast(0f)
            }
        }
    }

    private fun collapseToPill() {
        expandedBar.visibility = View.GONE
        collapsedPill.visibility = View.VISIBLE
    }

    private fun toggleKeyboard() {
        X11KeyboardReceiver.performToggleKeyboard(activity)
    }

    private fun openPreferences() {
        try {
            val intent = Intent(activity, Class.forName("com.termux.x11.LoriePreferences"))
            activity.startActivity(intent)
        } catch (_: Throwable) {
            val intent = Intent("com.termux.x11.CHANGE_PREFERENCE")
            activity.sendBroadcast(intent)
        }
    }

    private fun returnToHub() {
        // Return to Flutter MainActivity
        try {
            val intent = Intent(activity, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
            }
            activity.startActivity(intent)
        } catch (_: Throwable) {
            activity.finish()
        }
    }

    private val scaleLevels = intArrayOf(100, 125, 150, 175, 200)
    private var scaleIndex = 2
    private var scaleBtn: TextView? = null

    private fun toggleScaleFactor() {
        scaleIndex = (scaleIndex + 1) % scaleLevels.size
        val nextScale = scaleLevels[scaleIndex]
        scaleBtn?.text = "📐 ${nextScale}%"
        val intent = Intent("com.termux.x11.CHANGE_PREFERENCE").apply {
            putExtra("displayScale", nextScale.toString())
            setPackage(activity.packageName)
        }
        activity.sendBroadcast(intent)
    }

    companion object {
        private const val OVERLAY_TAG = "intelnode_x11_overlay"

        fun attach(activity: Activity) {
            val root = activity.findViewById<ViewGroup>(android.R.id.content)
                ?: (activity.window.decorView as? ViewGroup)
            if (root?.findViewWithTag<View>(OVERLAY_TAG) != null) {
                return // Already attached
            }
            val overlay = X11FloatingOverlay(activity)
            overlay.container.tag = OVERLAY_TAG
        }
    }
}
