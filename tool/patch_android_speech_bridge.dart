import 'dart:io';

void main() {
  final file = File(
    'android/app/src/main/kotlin/com/yunfei/family/family_home_manager/MainActivity.kt',
  );

  if (!file.existsSync()) {
    stderr.writeln('MainActivity.kt not found. Run flutter create first.');
    exitCode = 1;
    return;
  }

  file.writeAsStringSync(r'''package com.yunfei.family.family_home_manager

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "family_home_manager/speech"
    private val speechRequestCode = 4107
    private val audioPermissionRequestCode = 4108

    private var pendingSpeechResult: MethodChannel.Result? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var speechRecognizer: SpeechRecognizer? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var recognitionTimeout: Runnable? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCapabilities" -> {
                    result.success(
                        mapOf(
                            "serviceAvailable" to isSpeechServiceAvailable(),
                            "onDeviceAvailable" to isOnDeviceSpeechAvailable(),
                            "activityAvailable" to isSpeechActivityAvailable(),
                            "audioPermission" to hasAudioPermission()
                        )
                    )
                }

                "requestAudioPermission" -> {
                    if (hasAudioPermission()) {
                        result.success(true)
                    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        if (pendingPermissionResult != null) {
                            result.error(
                                "permission_busy",
                                "An audio permission request is already active.",
                                null
                            )
                        } else {
                            pendingPermissionResult = result
                            requestPermissions(
                                arrayOf(Manifest.permission.RECORD_AUDIO),
                                audioPermissionRequestCode
                            )
                        }
                    } else {
                        result.success(true)
                    }
                }

                "recognizeOnce" -> {
                    if (pendingSpeechResult != null) {
                        result.error(
                            "busy",
                            "A speech recognition request is already active.",
                            null
                        )
                        return@setMethodCallHandler
                    }

                    if (!hasAudioPermission()) {
                        result.error(
                            "permission_denied",
                            "Microphone permission is required.",
                            null
                        )
                        return@setMethodCallHandler
                    }

                    val locale =
                        call.argument<String>("locale") ?: "zh-CN"
                    val prompt =
                        call.argument<String>("prompt")
                            ?: "请说出要录入的家庭物品"

                    when {
                        isSpeechServiceAvailable() -> {
                            startDirectRecognition(
                                locale = locale,
                                result = result
                            )
                        }

                        isSpeechActivityAvailable() -> {
                            startActivityRecognition(
                                locale = locale,
                                prompt = prompt,
                                result = result
                            )
                        }

                        else -> {
                            result.error(
                                "not_available",
                                "No Android speech recognition service or activity is available.",
                                null
                            )
                        }
                    }
                }

                "cancelRecognition" -> {
                    cleanupRecognizer(cancel = true)
                    val callback = pendingSpeechResult
                    pendingSpeechResult = null
                    callback?.success(null)
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun hasAudioPermission(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
                PackageManager.PERMISSION_GRANTED
    }

    private fun isSpeechServiceAvailable(): Boolean {
        return try {
            SpeechRecognizer.isRecognitionAvailable(this)
        } catch (_: Throwable) {
            false
        }
    }

    private fun isOnDeviceSpeechAvailable(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            try {
                SpeechRecognizer.isOnDeviceRecognitionAvailable(this)
            } catch (_: Throwable) {
                false
            }
    }

    private fun isSpeechActivityAvailable(): Boolean {
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
        return packageManager.queryIntentActivities(
            intent,
            PackageManager.MATCH_DEFAULT_ONLY
        ).isNotEmpty()
    }

    private fun startDirectRecognition(
        locale: String,
        result: MethodChannel.Result
    ) {
        pendingSpeechResult = result

        val recognizer = try {
            if (
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                SpeechRecognizer.isOnDeviceRecognitionAvailable(this)
            ) {
                SpeechRecognizer.createOnDeviceSpeechRecognizer(this)
            } else {
                SpeechRecognizer.createSpeechRecognizer(this)
            }
        } catch (error: Throwable) {
            pendingSpeechResult = null
            result.error(
                "create_failed",
                error.message ?: "Unable to create SpeechRecognizer.",
                null
            )
            return
        }

        speechRecognizer = recognizer
        recognizer.setRecognitionListener(
            object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) {}
                override fun onBeginningOfSpeech() {}
                override fun onRmsChanged(rmsdB: Float) {}
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onEndOfSpeech() {}

                override fun onError(error: Int) {
                    finishRecognitionError(
                        "recognition_error",
                        speechErrorMessage(error)
                    )
                }

                override fun onResults(results: Bundle?) {
                    val matches = results?.getStringArrayList(
                        SpeechRecognizer.RESULTS_RECOGNITION
                    )
                    finishRecognitionSuccess(matches?.firstOrNull())
                }

                override fun onPartialResults(partialResults: Bundle?) {}
                override fun onEvent(eventType: Int, params: Bundle?) {}
            }
        )

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
            )
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE,
                locale
            )
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, false)
        }

        val timeout = Runnable {
            finishRecognitionError(
                "timeout",
                "Speech recognition timed out."
            )
        }
        recognitionTimeout = timeout
        mainHandler.postDelayed(timeout, 35000)

        try {
            recognizer.startListening(intent)
        } catch (error: Throwable) {
            finishRecognitionError(
                "start_failed",
                error.message ?: "Unable to start speech recognition."
            )
        }
    }

    private fun startActivityRecognition(
        locale: String,
        prompt: String,
        result: MethodChannel.Result
    ) {
        pendingSpeechResult = result

        val intent = Intent(
            RecognizerIntent.ACTION_RECOGNIZE_SPEECH
        ).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
            )
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE,
                locale
            )
            putExtra(RecognizerIntent.EXTRA_PROMPT, prompt)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
        }

        try {
            startActivityForResult(intent, speechRequestCode)
        } catch (error: ActivityNotFoundException) {
            pendingSpeechResult = null
            result.error(
                "not_available",
                "No system speech recognition activity is available.",
                null
            )
        } catch (error: Exception) {
            pendingSpeechResult = null
            result.error(
                "launch_failed",
                error.message,
                null
            )
        }
    }

    private fun finishRecognitionSuccess(text: String?) {
        val callback = pendingSpeechResult
        pendingSpeechResult = null
        cleanupRecognizer(cancel = false)
        callback?.success(text)
    }

    private fun finishRecognitionError(code: String, message: String) {
        val callback = pendingSpeechResult
        pendingSpeechResult = null
        cleanupRecognizer(cancel = true)
        callback?.error(code, message, null)
    }

    private fun cleanupRecognizer(cancel: Boolean) {
        recognitionTimeout?.let {
            mainHandler.removeCallbacks(it)
        }
        recognitionTimeout = null

        val recognizer = speechRecognizer
        speechRecognizer = null
        if (recognizer != null) {
            try {
                if (cancel) {
                    recognizer.cancel()
                } else {
                    recognizer.stopListening()
                }
            } catch (_: Throwable) {
            }
            try {
                recognizer.destroy()
            } catch (_: Throwable) {
            }
        }
    }

    private fun speechErrorMessage(error: Int): String {
        return when (error) {
            SpeechRecognizer.ERROR_AUDIO -> "Audio recording error."
            SpeechRecognizer.ERROR_CLIENT -> "Speech recognition client error."
            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS ->
                "Microphone permission was denied."
            SpeechRecognizer.ERROR_NETWORK -> "Speech recognition network error."
            SpeechRecognizer.ERROR_NETWORK_TIMEOUT ->
                "Speech recognition network timeout."
            SpeechRecognizer.ERROR_NO_MATCH -> "No speech was recognized."
            SpeechRecognizer.ERROR_RECOGNIZER_BUSY ->
                "Speech recognizer is busy."
            SpeechRecognizer.ERROR_SERVER ->
                "Speech recognition server error."
            SpeechRecognizer.ERROR_SPEECH_TIMEOUT ->
                "No speech input was detected."
            else -> "Speech recognition error code: $error"
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        if (requestCode == audioPermissionRequestCode) {
            val callback = pendingPermissionResult
            pendingPermissionResult = null
            callback?.success(
                grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED
            )
            return
        }
        super.onRequestPermissionsResult(
            requestCode,
            permissions,
            grantResults
        )
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?
    ) {
        if (requestCode == speechRequestCode) {
            val callback = pendingSpeechResult
            pendingSpeechResult = null

            if (callback == null) {
                super.onActivityResult(requestCode, resultCode, data)
                return
            }

            if (resultCode == Activity.RESULT_OK) {
                val matches = data?.getStringArrayListExtra(
                    RecognizerIntent.EXTRA_RESULTS
                )
                callback.success(matches?.firstOrNull())
            } else {
                callback.success(null)
            }
            return
        }

        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        cleanupRecognizer(cancel = true)
        pendingSpeechResult = null
        pendingPermissionResult = null
        super.onDestroy()
    }
}
''');
}
