package com.notia.os.notia

import android.content.ContentUris
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.CalendarContract
import android.provider.Settings
import android.webkit.WebView
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

// FlutterFragmentActivity é exigido pelo local_auth (biometria).
class MainActivity : FlutterFragmentActivity() {
    // pauseTimers/resumeTimers afetam todos os WebViews do processo.
    private val timerHandle: WebView by lazy { WebView(applicationContext) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        EventChannel(messenger, "notia/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, events: EventChannel.EventSink?) {
                NotiaBridge.attach(events)
            }

            override fun onCancel(args: Any?) {
                NotiaBridge.attach(null)
            }
        })

        MethodChannel(messenger, "notia/system").setMethodCallHandler { call, result ->
            try {
                handle(call, result)
            } catch (e: Exception) {
                result.error("native", e.message, null)
            }
        }
        SystemKit.startWatching(applicationContext)
        handleIntent(intent)
    }

    override fun onDestroy() {
        SystemKit.stopWatching(applicationContext)
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        val svc = NotiaAccessibilityService.instance
        when (call.method) {
            "pauseWebTimers" -> { timerHandle.pauseTimers(); result.success(null) }
            "resumeWebTimers" -> { timerHandle.resumeTimers(); result.success(null) }

            // ----- Acessibilidade (agente de apps) -----
            "a11y.enabled" -> result.success(svc != null)
            "a11y.snapshot" -> result.success(svc?.snapshot())
            "a11y.click" -> result.success(svc?.clickIndex(call.argument<Int>("index") ?: -1) ?: false)
            "a11y.setText" -> result.success(
                svc?.setText(call.argument<Int>("index") ?: -1, call.argument<String>("text") ?: "") ?: false
            )
            "a11y.scroll" -> result.success(svc?.scroll(call.argument<Boolean>("down") ?: true) ?: false)
            "a11y.back" -> result.success(svc?.back() ?: false)
            "a11y.home" -> result.success(svc?.home() ?: false)
            "a11y.overlay" -> {
                if (call.argument<Boolean>("show") == false) svc?.hideOverlay()
                else svc?.showOverlay(call.argument<String>("text") ?: "Notia agindo…")
                result.success(null)
            }
            "a11y.confirm" -> {
                svc?.showConfirm(call.argument<String>("text") ?: "Permitir?")
                    ?: NotiaBridge.emit(mapOf("type" to "agent_confirm", "ok" to false))
                result.success(null)
            }
            "a11y.package" -> result.success(svc?.currentPackage ?: "")

            // ----- Notificações -----
            "notif.enabled" -> {
                val s = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
                result.success(s?.contains(packageName) == true)
            }
            "notif.recent" -> result.success(NotiaNotificationListener.snapshot(call.argument<Int>("limit") ?: 50))
            "notif.clear" -> { NotiaNotificationListener.clear(); result.success(null) }

            // ----- Calendário do aparelho -----
            "calendar.events" -> result.success(
                calendarEvents(call.argument<Number>("from")!!.toLong(), call.argument<Number>("to")!!.toLong())
            )

            // ----- Painel do aparelho (OpenEXE) -----
            "sys.stats" -> result.success(SystemKit.stats(this))
            "sec.info" -> result.success(SystemKit.secInfo(this))
            "opt.info" -> result.success(SystemKit.optInfo(this))
            "opt.clearCache" -> result.success(SystemKit.clearCache(this))
            "sys.bluetooth" -> result.success(SystemKit.bluetoothOn(this))
            "sys.keyboard" -> result.success(SystemKit.physicalKeyboard())
            "app.quick" -> result.success(SystemKit.quick(this, call.argument<String>("which") ?: ""))
            "app.uninstall" -> result.success(SystemKit.uninstall(this, call.argument<String>("pkg") ?: ""))
            "app.info" -> result.success(SystemKit.appInfo(this, call.argument<String>("pkg") ?: ""))
            "alarm.set" -> result.success(
                SystemKit.setAlarm(
                    this,
                    call.argument<Int>("hour") ?: 7,
                    call.argument<Int>("minute") ?: 0,
                    call.argument<String>("label") ?: "OpenEXE"
                )
            )
            "alarm.next" -> result.success(SystemKit.nextAlarm(this))
            "keepalive" -> result.success(SystemKit.keepAlive(this, call.argument<Boolean>("on") ?: false))
            "a11y.hideConfirm" -> { svc?.hideConfirm(); result.success(null) }
            "update.dir" -> result.success(SystemKit.updateDir(this))
            "update.install" -> result.success(SystemKit.installApk(this, call.argument<String>("path") ?: ""))
            "sys.homeSettings" -> result.success(SystemKit.homeSettings(this))
            "clip.image" -> result.success(SystemKit.clipImage(this))
            "clip.setImage" -> result.success(SystemKit.setClipImage(this, call.argument<String>("path") ?: ""))

            // ----- Telas de configuração do Android -----
            "openSettings" -> {
                val pkg = Uri.parse("package:$packageName")
                val i = when (call.argument<String>("which")) {
                    "accessibility" -> Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                    "notifications" -> Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                    "appdetails" -> Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, pkg)
                    "battery" -> Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                    "ignorebattery" -> Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, pkg)
                    "batterysaver" -> Intent(Settings.ACTION_BATTERY_SAVER_SETTINGS)
                    "usage" -> Intent(Intent.ACTION_POWER_USAGE_SUMMARY)
                    "storage" -> Intent(Settings.ACTION_INTERNAL_STORAGE_SETTINGS)
                    "apps" -> Intent(Settings.ACTION_MANAGE_ALL_APPLICATIONS_SETTINGS)
                    "data" -> Intent(Settings.ACTION_DATA_USAGE_SETTINGS)
                    "security" -> Intent(Settings.ACTION_SECURITY_SETTINGS)
                    "developer" -> Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS)
                    "installunknown" -> Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, pkg)
                    "location" -> Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)
                    else -> null
                }
                var ok = false
                if (i != null) {
                    i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    try {
                        startActivity(i)
                        ok = true
                    } catch (e: Exception) {
                        try {
                            startActivity(Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                            ok = true
                        } catch (e2: Exception) { }
                    }
                }
                result.success(ok)
            }
            else -> result.notImplemented()
        }
    }

    // ---------- Compartilhar para o Notia e atalho do painel rápido ----------
    private fun handleIntent(i: Intent?) {
        if (i == null) return
        if (i.action == Intent.ACTION_SEND) {
            val type = i.type ?: ""
            if (type.startsWith("text/")) {
                val t = i.getStringExtra(Intent.EXTRA_TEXT)
                if (!t.isNullOrBlank()) {
                    NotiaBridge.emit(
                        mapOf(
                            "type" to "share", "kind" to "text", "text" to t,
                            "subject" to (i.getStringExtra(Intent.EXTRA_SUBJECT) ?: "")
                        )
                    )
                }
            } else if (type.startsWith("image/")) {
                val uri: Uri? = if (Build.VERSION.SDK_INT >= 33) {
                    i.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    i.getParcelableExtra(Intent.EXTRA_STREAM)
                }
                if (uri != null) {
                    try {
                        val f = File(cacheDir, "share_${System.currentTimeMillis()}.jpg")
                        contentResolver.openInputStream(uri)?.use { input ->
                            f.outputStream().use { input.copyTo(it) }
                        }
                        NotiaBridge.emit(mapOf("type" to "share", "kind" to "image", "path" to f.absolutePath))
                    } catch (_: Exception) {
                    }
                }
            }
            i.action = Intent.ACTION_MAIN
        }
        val a = i.getStringExtra("notia_action")
        if (a != null) {
            NotiaBridge.emit(mapOf("type" to "action", "action" to a))
            i.removeExtra("notia_action")
        }
    }

    private fun calendarEvents(from: Long, to: Long): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        val b = CalendarContract.Instances.CONTENT_URI.buildUpon()
        ContentUris.appendId(b, from)
        ContentUris.appendId(b, to)
        val proj = arrayOf(
            CalendarContract.Instances.TITLE,
            CalendarContract.Instances.BEGIN,
            CalendarContract.Instances.END,
            CalendarContract.Instances.ALL_DAY,
            CalendarContract.Instances.EVENT_LOCATION
        )
        contentResolver.query(b.build(), proj, null, null, "${CalendarContract.Instances.BEGIN} ASC")
            ?.use { c ->
                while (c.moveToNext() && out.size < 50) {
                    out.add(
                        mapOf(
                            "title" to (c.getString(0) ?: ""),
                            "begin" to c.getLong(1),
                            "end" to c.getLong(2),
                            "allDay" to (c.getInt(3) == 1),
                            "where" to (c.getString(4) ?: "")
                        )
                    )
                }
            }
        return out
    }
}
