# Debug Report: com.fct.da_ripped_tiny_computer (Tiny Computer Fork)
**Date:** Tuesday, March 3, 2026
**Status:** App Hang / Startup Freeze

## 1. Summary of Findings
The application hangs indefinitely during startup before the Flutter engine can fully initialize its UI. The root cause is a low-level graphics allocation failure within the Android `gralloc5` hardware abstraction layer (HAL).

## 2. Technical Root Cause
The system logs show repeated fatal errors from `gralloc5` when the app attempts to allocate a drawing surface:
- **Error:** `ERROR: Unrecognized and/or unsupported format (<unrecognized format> 0x3b)`
- **Context:** The Flutter engine is requesting a graphics buffer format `0x3b` with usage flags `(CPU_READ_NEVER|CPU_WRITE_NEVER|GPU_TEXTURE|GPU_RENDER_TARGET|COMPOSER_OVERLAY)`.
- **Result:** The hardware composer (HWC) and Gralloc service reject the request, causing the Flutter UI thread to block indefinitely waiting for a valid surface.

## 3. Evidence (Logcat Snippets)
```text
03-03 15:23:38.633   521  4043 E gralloc5: ERROR: Format allocation info not found for format: 3b
03-03 15:23:38.633   521  4043 E gralloc5: Invalid base format! req_base_format = (<unrecognized format> 0x0), req_format = (<unrecognized format> 0x3b), type = 0x0
03-03 15:23:38.633   521  4043 E gralloc5: ERROR: Unrecognized and/or unsupported format (<unrecognized format> 0x3b) and usage (0xb00)
03-03 15:23:54.779  1732  1732 W AccessibilityManagerService: wait for adding window timeout: 1156
```

## 4. Observations on App Architecture
The app includes several specialized native libraries:
- `libflutter_pty.so` (Pseudo-terminal support)
- `libnative-vnc.so` (VNC engine)
- `libnative-socket.so` (Socket handling)
- `libXlorie.so` (Likely X11/XWayland server integration)

The hang may be exacerbated if `libXlorie.so` is attempting to initialize a native surface using an incompatible pixel format or if the Flutter `Texture` widget is being used with an unsupported external texture format.

## 5. Recommended Next Steps
1. **Check Flutter Engine Version:** Ensure the project is using a stable Flutter version compatible with modern Android 14+ Gralloc requirements.
2. **Review Native Surface Initialization:** If the app uses `SurfaceView` or `TextureView` via `AndroidView` or `ExternalTexture`, verify the requested pixel format (likely `PixelFormat.RGBA_8888` or similar).
3. **Disable Hardware Acceleration (Test):** As a temporary diagnostic, try disabling hardware acceleration for the activity in `AndroidManifest.xml` (`android:hardwareAccelerated="false"`) to see if the app boots into a software-rendered state.
4. **Inspect `libXlorie.so`:** Check if this library is hard-coding graphics formats that aren't supported on the current device's GPU/SoC.
