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

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.speech.RecognizerIntent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "family_home_manager/speech"
    private val speechRequestCode = 4107
    private var pendingSpeechResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "recognizeOnce" -> {
                    if (pendingSpeechResult != null) {
                        result.error(
                            "busy",
                            "A speech recognition request is already active.",
                            null
                        )
                        return@setMethodCallHandler
                    }

                    val locale =
                        call.argument<String>("locale") ?: "zh-CN"
                    val prompt =
                        call.argument<String>("prompt")
                            ?: "请说出要录入的家庭物品"

                    val intent = Intent(
                        RecognizerIntent.ACTION_RECOGNIZE_SPEECH
                    ).apply {
                        putExtra(
                            RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                            RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
                        )
                        putExtra(
                            RecognizerIntent.EXTRA_LANGUAGE,
                            locale
                        )
                        putExtra(
                            RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE,
                            locale
                        )
                        putExtra(
                            RecognizerIntent.EXTRA_PROMPT,
                            prompt
                        )
                        putExtra(
                            RecognizerIntent.EXTRA_MAX_RESULTS,
                            1
                        )
                    }

                    try {
                        pendingSpeechResult = result
                        startActivityForResult(
                            intent,
                            speechRequestCode
                        )
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

                else -> result.notImplemented()
            }
        }
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
                super.onActivityResult(
                    requestCode,
                    resultCode,
                    data
                )
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
}
''');
}
