import 'dart:io';

void main() {
  final kotlinDir = Directory(
    'android/app/src/main/kotlin/com/yunfei/family/family_home_manager',
  );
  final mainActivity = File('${kotlinDir.path}/MainActivity.kt');
  final manifest = File('android/app/src/main/AndroidManifest.xml');

  if (!mainActivity.existsSync() || !manifest.existsSync()) {
    stderr.writeln('Android platform files not found. Run flutter create first.');
    exitCode = 1;
    return;
  }

  final receiver = File('${kotlinDir.path}/ReminderReceiver.kt');
  receiver.writeAsStringSync(r'''package com.yunfei.family.family_home_manager

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (
            Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            return
        }

        val notificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        ensureChannel(notificationManager)

        val id = intent.getIntExtra("id", 0)
        val title = intent.getStringExtra("title") ?: "家庭管理提醒"
        val body = intent.getStringExtra("body") ?: ""

        val launchIntent = context.packageManager
            .getLaunchIntentForPackage(context.packageName)
            ?.apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }

        val contentIntent = launchIntent?.let {
            PendingIntent.getActivity(
                context,
                id,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            android.app.Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            android.app.Notification.Builder(context)
        }

        builder
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(android.app.Notification.BigTextStyle().bigText(body))
            .setAutoCancel(true)

        if (contentIntent != null) {
            builder.setContentIntent(contentIntent)
        }

        notificationManager.notify(id, builder.build())
    }

    companion object {
        const val CHANNEL_ID = "family_reminders"
        const val CHANNEL_NAME = "家庭提醒"

        fun ensureChannel(manager: NotificationManager) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                manager.createNotificationChannel(
                    NotificationChannel(
                        CHANNEL_ID,
                        CHANNEL_NAME,
                        NotificationManager.IMPORTANCE_DEFAULT
                    ).apply {
                        description = "库存不足、保质期和同步冲突提醒"
                    }
                )
            }
        }
    }
}
''');

  final bridge = File('${kotlinDir.path}/ReminderBridge.kt');
  bridge.writeAsStringSync(r'''package com.yunfei.family.family_home_manager

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

object ReminderBridge {
    private const val CHANNEL = "family_home_manager/reminders"
    private const val PERMISSION_REQUEST_CODE = 4201

    fun configure(
        activity: MainActivity,
        flutterEngine: FlutterEngine
    ) {
        val manager =
            activity.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        ReminderReceiver.ensureChannel(manager)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermission" -> {
                    if (
                        Build.VERSION.SDK_INT >= 33 &&
                        activity.checkSelfPermission(
                            Manifest.permission.POST_NOTIFICATIONS
                        ) != PackageManager.PERMISSION_GRANTED
                    ) {
                        activity.requestPermissions(
                            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                            PERMISSION_REQUEST_CODE
                        )
                    }
                    result.success(true)
                }

                "areNotificationsEnabled" -> {
                    val enabled =
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                            manager.areNotificationsEnabled()
                        } else {
                            true
                        }
                    result.success(enabled)
                }

                "showNow" -> {
                    val id = call.argument<Int>("id") ?: 0
                    val title =
                        call.argument<String>("title") ?: "家庭管理提醒"
                    val body = call.argument<String>("body") ?: ""
                    ReminderReceiver().onReceive(
                        activity,
                        reminderIntent(activity, id, title, body)
                    )
                    result.success(true)
                }

                "schedule" -> {
                    val id = call.argument<Int>("id")
                    val triggerAt = call.argument<Number>("triggerAt")?.toLong()
                    val title = call.argument<String>("title")
                    val body = call.argument<String>("body")
                    if (
                        id == null ||
                        triggerAt == null ||
                        title == null ||
                        body == null
                    ) {
                        result.error("bad_args", "Missing reminder arguments", null)
                        return@setMethodCallHandler
                    }

                    val alarmManager =
                        activity.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                    val pending = reminderPendingIntent(
                        activity,
                        id,
                        title,
                        body
                    )
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        alarmManager.setAndAllowWhileIdle(
                            AlarmManager.RTC_WAKEUP,
                            triggerAt,
                            pending
                        )
                    } else {
                        alarmManager.set(
                            AlarmManager.RTC_WAKEUP,
                            triggerAt,
                            pending
                        )
                    }
                    result.success(true)
                }

                "cancelMany" -> {
                    val ids = call.argument<List<Int>>("ids") ?: emptyList()
                    val alarmManager =
                        activity.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                    for (id in ids) {
                        val pending = PendingIntent.getBroadcast(
                            activity,
                            id,
                            Intent(activity, ReminderReceiver::class.java),
                            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
                        )
                        if (pending != null) {
                            alarmManager.cancel(pending)
                            pending.cancel()
                        }
                    }
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun reminderPendingIntent(
        context: Context,
        id: Int,
        title: String,
        body: String
    ): PendingIntent {
        return PendingIntent.getBroadcast(
            context,
            id,
            reminderIntent(context, id, title, body),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun reminderIntent(
        context: Context,
        id: Int,
        title: String,
        body: String
    ): Intent {
        return Intent(context, ReminderReceiver::class.java).apply {
            putExtra("id", id)
            putExtra("title", title)
            putExtra("body", body)
        }
    }
}
''');

  mainActivity.writeAsStringSync(r'''package com.yunfei.family.family_home_manager

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ReminderBridge.configure(this, flutterEngine)
    }
}
''');

  var manifestContent = manifest.readAsStringSync();
  const manifestMarker =
      '<manifest xmlns:android="http://schemas.android.com/apk/res/android">';
  const permission =
      '    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />';
  if (!manifestContent.contains(permission)) {
    manifestContent = manifestContent.replaceFirst(
      manifestMarker,
      '$manifestMarker\n$permission',
    );
  }

  const receiverEntry =
      '        <receiver android:name=".ReminderReceiver" android:exported="false" />';
  if (!manifestContent.contains(receiverEntry)) {
    const applicationClose = '    </application>';
    manifestContent = manifestContent.replaceFirst(
      applicationClose,
      '$receiverEntry\n$applicationClose',
    );
  }

  manifest.writeAsStringSync(manifestContent);
}
