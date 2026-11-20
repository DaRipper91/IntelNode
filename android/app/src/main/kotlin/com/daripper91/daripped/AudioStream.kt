package com.daripper91.daripped

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.util.Log

object AudioStream {
    // False when libnative-socket.so is missing or does not match the JNI symbols below; every
    // native call is guarded by this so a bad build fails the feature instead of the process.
    private val nativeLoaded: Boolean = try {
        System.loadLibrary("native-socket")
        true
    } catch (t: Throwable) {
        Log.e("AudioStream", "Failed to load native-socket", t)
        false
    }

    // Written by the platform thread, read by the recording thread.
    @Volatile
    private var isStreaming = false
    private var recordingThread: Thread? = null

    // Native functions
    private external fun nativeInit(path: String): Int
    private external fun nativeAccept(): Int
    private external fun nativeSend(data: ByteArray, size: Int): Int
    private external fun nativeClose()

    @SuppressLint("MissingPermission") // Ensure RECORD_AUDIO is granted in Manifest
    @Synchronized
    fun startStreaming(path: String): Boolean {
        if (!nativeLoaded) return false
        if (isStreaming) return true
        // A previous worker may still be winding down after stopStreaming().
        if (recordingThread?.isAlive == true) return false
        isStreaming = true

        recordingThread = Thread {
          try {
            // 1. Initialize Socket Server
            if (nativeInit(path) < 0) {
                Log.e("AudioStream", "Failed to bind socket")
                isStreaming = false
                return@Thread
            }

            // 2. Wait for Linux client to connect (Blocking)
            Log.d("AudioStream", "Waiting for connection on $path...")
            if (nativeAccept() < 0) {
                Log.e("AudioStream", "Accept failed")
                isStreaming = false
                return@Thread
            }
            Log.d("AudioStream", "Client connected!")

            // 3. Setup AudioRecord
            val sampleRate = 44100
            val bufferSize = AudioRecord.getMinBufferSize(
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT
            )

            if (bufferSize <= 0) {
                // ERROR / ERROR_BAD_VALUE are negative; ByteArray(bufferSize) would throw.
                Log.e("AudioStream", "Invalid AudioRecord buffer size: $bufferSize")
                isStreaming = false
                nativeClose()
                return@Thread
            }

            val recorder = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferSize
            )

            if (recorder.state != AudioRecord.STATE_INITIALIZED) {
                Log.e("AudioStream", "AudioRecord failed to initialise")
                recorder.release()
                isStreaming = false
                nativeClose()
                return@Thread
            }

            val data = ByteArray(bufferSize)
            try {
                recorder.startRecording()
            } catch (e: IllegalStateException) {
                Log.e("AudioStream", "startRecording failed", e)
                recorder.release()
                isStreaming = false
                nativeClose()
                return@Thread
            }

            val discardMillis = 5000 // 丢弃前5秒
            val discardBytes = (sampleRate * 2 * discardMillis / 1000).toInt() // 16bit = 2字节
            var bytesRead = 0

            // 先读取并丢弃初始数据
            while (bytesRead < discardBytes && isStreaming) {
                val readBytes = recorder.read(data, 0, minOf(bufferSize, discardBytes - bytesRead))
                if (readBytes > 0) {
                    bytesRead += readBytes
                } else {
                    Thread.sleep(10) // error or no data: do not spin
                }
            }

            // 4. Streaming Loop
            while (isStreaming) {
                val readBytes = recorder.read(data, 0, bufferSize)
                if (readBytes > 0) {
                    val sent = nativeSend(data, readBytes)
                    if (sent < 0) break // Socket broken
                } else {
                    Thread.sleep(10) // error or no data: do not spin
                }
            }

            // Cleanup
            recorder.stop()
            recorder.release()
            nativeClose()
          } catch (t: Throwable) {
            Log.e("AudioStream", "Streaming worker failed", t)
            try { nativeClose() } catch (_: Throwable) {}
          } finally {
            // Every exit path (socket broken, bind/accept failure, exception) must allow a restart.
            isStreaming = false
          }
        }
        recordingThread?.start()
        return true
    }

    @Synchronized
    fun stopStreaming() {
        isStreaming = false
        if (nativeLoaded) {
            try {
                nativeClose() // Unblocks the native Accept/Send if hung
            } catch (t: Throwable) {
                Log.e("AudioStream", "nativeClose failed", t)
            }
        }
        // Do not join here: stopStreaming runs on the platform thread. The worker exits on its own
        // (isStreaming is false and the socket is closed); startStreaming refuses to start while it
        // is still alive, so a restart cannot overlap the old worker.
    }
    }
}