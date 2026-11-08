package com.notia.os.notia

import android.app.ActivityManager
import android.bluetooth.BluetoothAdapter
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.input.InputManager
import android.net.Uri
import android.os.BatteryManager
import android.os.Environment
import android.os.Process
import android.os.StatFs
import android.os.SystemClock
import android.provider.AlarmClock
import android.provider.MediaStore
import android.provider.Settings
import android.view.InputDevice
import androidx.core.content.FileProvider
import java.io.File

/**
 * Recursos do aparelho para o painel do OpenEXE: RAM, memória, CPU, temperatura,
 * Bluetooth, teclado físico, apps rápidos e imagens da área de transferência.
 *
 * Limites do Android 13: /proc/stat costuma ser bloqueado para apps comuns. Quando não dá
 * para ler, a CPU vem da frequência atual / frequência máxima e, em último caso, do uso do
 * próprio processo. O campo "cpuSource" diz qual fonte foi usada.
 */
object SystemKit {
    // ---------- Monitor ----------
    private var lastTotal = 0L
    private var lastIdle = 0L
    private var lastProcCpuMs = 0L
    private var lastWallMs = 0L

    fun stats(ctx: Context): Map<String, Any?> {
        val out = HashMap<String, Any?>()

        val am = ctx.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val mi = ActivityManager.MemoryInfo()
        am.getMemoryInfo(mi)
        out["ramTotal"] = mi.totalMem
        out["ramAvail"] = mi.availMem

        val st = StatFs(Environment.getDataDirectory().path)
        out["storTotal"] = st.totalBytes
        out["storFree"] = st.availableBytes

        val cores = Runtime.getRuntime().availableProcessors()
        out["cores"] = cores

        // CPU: 1) /proc/stat  2) frequência  3) processo próprio
        var pct = -1
        var src = "none"
        val stat = readCpuStat()
        if (stat != null) {
            val (total, idle) = stat
            if (lastTotal > 0 && total > lastTotal) {
                val dt = (total - lastTotal).toDouble()
                val di = (idle - lastIdle).toDouble()
                pct = (((dt - di) / dt) * 100).toInt().coerceIn(0, 100)
                src = "stat"
            }
            lastTotal = total
            lastIdle = idle
        }
        val cur = readLong("/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq")
        val max = readLong("/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq")
        if (cur > 0) out["cpuMHz"] = (cur / 1000).toInt()
        if (max > 0) out["cpuMaxMHz"] = (max / 1000).toInt()
        if (pct < 0 && cur > 0 && max > 0) {
            pct = ((cur.toDouble() / max) * 100).toInt().coerceIn(0, 100)
            src = "freq"
        }
        val procMs = Process.getElapsedCpuTime()
        val wall = SystemClock.elapsedRealtime()
        if (pct < 0 && lastWallMs > 0 && wall > lastWallMs) {
            pct = (((procMs - lastProcCpuMs).toDouble() / ((wall - lastWallMs) * cores)) * 100)
                .toInt().coerceIn(0, 100)
            src = "app"
        }
        lastProcCpuMs = procMs
        lastWallMs = wall
        out["cpuPct"] = pct
        out["cpuSource"] = src

        // Temperatura: zona térmica (se legível) ou bateria.
        var temp = -1.0
        var tsrc = "none"
        val tz = File("/sys/class/thermal").listFiles { f -> f.name.startsWith("thermal_zone") }
        if (tz != null) {
            for (z in tz) {
                val t = readLong(File(z, "temp").path)
                if (t > 0) {
                    val c = if (t > 1000) t / 1000.0 else t.toDouble()
                    if (c in 10.0..120.0 && c > temp) {
                        temp = c
                        tsrc = "thermal"
                    }
                }
            }
        }
        val bi = ctx.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val bt = bi?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1) ?: -1
        if (bt > 0) {
            out["battTemp"] = bt / 10.0
            if (temp < 0) {
                temp = bt / 10.0
                tsrc = "battery"
            }
        }
        out["temp"] = temp
        out["tempSource"] = tsrc
        return out
    }

    private fun readLong(path: String): Long = try {
        File(path).readText().trim().toLong()
    } catch (_: Exception) {
        -1L
    }

    private fun readCpuStat(): Pair<Long, Long>? = try {
        val line = File("/proc/stat").bufferedReader().use { it.readLine() }
        val p = line.trim().split(Regex("\\s+")).drop(1).map { it.toLong() }
        val idle = p[3] + (p.getOrNull(4) ?: 0L)
        Pair(p.sum(), idle)
    } catch (_: Exception) {
        null
    }

    // ---------- Bluetooth ----------
    fun bluetoothOn(ctx: Context): Boolean = try {
        Settings.Global.getInt(ctx.contentResolver, "bluetooth_on", 0) == 1
    } catch (_: Exception) {
        false
    }

    private var btReceiver: BroadcastReceiver? = null
    private var inputListener: InputManager.InputDeviceListener? = null

    /** Avisa o Flutter quando o Bluetooth liga/desliga e quando um teclado físico entra/sai. */
    fun startWatching(ctx: Context) {
        if (btReceiver == null) {
            btReceiver = object : BroadcastReceiver() {
                override fun onReceive(c: Context, i: Intent) {
                    val s = i.getIntExtra(BluetoothAdapter.EXTRA_STATE, -1)
                    if (s == BluetoothAdapter.STATE_ON || s == BluetoothAdapter.STATE_OFF) {
                        NotiaBridge.emit(mapOf("type" to "bt", "on" to (s == BluetoothAdapter.STATE_ON)))
                    }
                }
            }
            ctx.registerReceiver(btReceiver, IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED))
        }
        if (inputListener == null) {
            val im = ctx.getSystemService(Context.INPUT_SERVICE) as InputManager
            val l = object : InputManager.InputDeviceListener {
                private fun ping() =
                    NotiaBridge.emit(mapOf("type" to "keyboard", "physical" to physicalKeyboard()))

                override fun onInputDeviceAdded(id: Int) = ping()
                override fun onInputDeviceRemoved(id: Int) = ping()
                override fun onInputDeviceChanged(id: Int) = ping()
            }
            inputListener = l
            im.registerInputDeviceListener(l, null)
        }
    }

    fun stopWatching(ctx: Context) {
        btReceiver?.let { try { ctx.unregisterReceiver(it) } catch (_: Exception) {} }
        btReceiver = null
        inputListener?.let {
            (ctx.getSystemService(Context.INPUT_SERVICE) as InputManager).unregisterInputDeviceListener(it)
        }
        inputListener = null
    }

    // ---------- Teclado físico ----------
    fun physicalKeyboard(): Boolean {
        for (id in InputDevice.getDeviceIds()) {
            val d = InputDevice.getDevice(id) ?: continue
            if (d.isVirtual) continue
            if (d.keyboardType == InputDevice.KEYBOARD_TYPE_ALPHABETIC &&
                (d.sources and InputDevice.SOURCE_KEYBOARD) == InputDevice.SOURCE_KEYBOARD
            ) return true
        }
        return false
    }

    // ---------- Apps rápidos do rodapé ----------
    fun quick(ctx: Context, which: String): Boolean {
        val i: Intent = when (which) {
            "clock" -> Intent(AlarmClock.ACTION_SHOW_ALARMS)
            "calculator" -> Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_APP_CALCULATOR)
            "calendar" -> Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_APP_CALENDAR)
            "camera" -> Intent(MediaStore.INTENT_ACTION_STILL_IMAGE_CAMERA)
            "recorder" -> Intent("android.provider.MediaStore.RECORD_SOUND")
            "settings" -> Intent(Settings.ACTION_SETTINGS)
            else -> return false
        }
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            ctx.startActivity(i)
            true
        } catch (_: Exception) {
            false
        }
    }

    fun uninstall(ctx: Context, pkg: String): Boolean = try {
        ctx.startActivity(
            Intent(Intent.ACTION_DELETE, Uri.parse("package:$pkg")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        true
    } catch (_: Exception) {
        false
    }

    fun appInfo(ctx: Context, pkg: String): Boolean = try {
        ctx.startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$pkg"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        true
    } catch (_: Exception) {
        false
    }

    // ---------- Imagens da área de transferência ----------
    /**
     * Se a área de transferência tem uma imagem, copia para o armazenamento do app e devolve
     * {path, size}. O Dart decide se é nova comparando o tamanho e o caminho já salvo.
     * O Android 10+ só deixa ler a área de transferência com o app em primeiro plano.
     */
    fun clipImage(ctx: Context): Map<String, Any?>? {
        val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clip = cm.primaryClip ?: return null
        if (clip.itemCount == 0) return null
        val uri = clip.getItemAt(0).uri ?: return null
        val type = ctx.contentResolver.getType(uri) ?: return null
        if (!type.startsWith("image/")) return null
        val dir = File(ctx.filesDir, "clip").apply { mkdirs() }
        val f = File(dir, "img_${System.currentTimeMillis()}.png")
        ctx.contentResolver.openInputStream(uri)?.use { input ->
            f.outputStream().use { input.copyTo(it) }
        } ?: return null
        if (f.length() == 0L) {
            f.delete()
            return null
        }
        return mapOf("path" to f.absolutePath, "size" to f.length())
    }

    /** Coloca uma imagem salva de volta na área de transferência (via FileProvider). */
    fun setClipImage(ctx: Context, path: String): Boolean = try {
        val f = File(path)
        val uri = FileProvider.getUriForFile(ctx, "${ctx.packageName}.clipprovider", f)
        val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        cm.setPrimaryClip(ClipData.newUri(ctx.contentResolver, "imagem", uri))
        true
    } catch (_: Exception) {
        false
    }

    // ---------- Atualização do app e troca de launcher ----------
    /** Pasta onde o APK baixado é guardado (coberta pelo FileProvider). */
    fun updateDir(ctx: Context): String = File(ctx.filesDir, "updates").apply { mkdirs() }.absolutePath

    /**
     * Abre o instalador do Android para o APK baixado. O Android sempre pede a confirmação
     * do usuário; sem a permissão "instalar apps desconhecidos" abre a tela para liberar.
     * Retorna "ok", "permissao" ou "erro".
     */
    fun installApk(ctx: Context, path: String): String = try {
        if (!ctx.packageManager.canRequestPackageInstalls()) {
            ctx.startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${ctx.packageName}"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            "permissao"
        } else {
            val uri = FileProvider.getUriForFile(ctx, "${ctx.packageName}.clipprovider", File(path))
            ctx.startActivity(
                Intent(Intent.ACTION_VIEW)
                    .setDataAndType(uri, "application/vnd.android.package-archive")
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            "ok"
        }
    } catch (_: Exception) {
        "erro"
    }

    /** Tela do Android onde se escolhe o launcher padrão (para voltar ao launcher original). */
    fun homeSettings(ctx: Context): Boolean = try {
        ctx.startActivity(Intent(Settings.ACTION_HOME_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (_: Exception) {
        try {
            ctx.startActivity(Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (_: Exception) {
            false
        }
    }

    // ---------- Despertador real (relógio do sistema) ----------
    /** Cria o alarme no app de Relógio do Android; ele toca mesmo com o OpenEXE fechado. */
    fun setAlarm(ctx: Context, hour: Int, minute: Int, label: String): Boolean = try {
        ctx.startActivity(
            Intent(AlarmClock.ACTION_SET_ALARM)
                .putExtra(AlarmClock.EXTRA_HOUR, hour)
                .putExtra(AlarmClock.EXTRA_MINUTES, minute)
                .putExtra(AlarmClock.EXTRA_MESSAGE, label)
                .putExtra(AlarmClock.EXTRA_SKIP_UI, true)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        true
    } catch (_: Exception) {
        false
    }

    /** Horário (ms) do próximo alarme do sistema, ou -1. */
    fun nextAlarm(ctx: Context): Long = try {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager
        am.nextAlarmClock?.triggerTime ?: -1L
    } catch (_: Exception) {
        -1L
    }

    // ---------- Serviço em primeiro plano ----------
    fun keepAlive(ctx: Context, on: Boolean): Boolean = try {
        val i = Intent(ctx, KeepAliveService::class.java)
        if (on) {
            if (android.os.Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(i) else ctx.startService(i)
        } else {
            ctx.stopService(i)
        }
        true
    } catch (_: Exception) {
        false
    }

    // ---------- Segurança e otimização (PAINEL) ----------
    private fun dirSize(f: File?): Long {
        if (f == null || !f.exists()) return 0L
        if (f.isFile) return f.length()
        var n = 0L
        f.listFiles()?.forEach { n += dirSize(it) }
        return n
    }

    private fun dirClear(f: File?): Long {
        if (f == null || !f.exists()) return 0L
        var n = 0L
        f.listFiles()?.forEach {
            val sz = dirSize(it)
            if (it.deleteRecursively()) n += sz
        }
        return n
    }

    fun secInfo(ctx: Context): Map<String, Any?> {
        val o = HashMap<String, Any?>()
        try {
            val km = ctx.getSystemService(Context.KEYGUARD_SERVICE) as android.app.KeyguardManager
            o["secure"] = km.isDeviceSecure
        } catch (e: Exception) { o["secure"] = null }
        o["patch"] = android.os.Build.VERSION.SECURITY_PATCH ?: ""
        o["release"] = android.os.Build.VERSION.RELEASE ?: ""
        o["sdk"] = android.os.Build.VERSION.SDK_INT
        o["model"] = "${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL}"
        try {
            o["dev"] = Settings.Global.getInt(ctx.contentResolver, Settings.Global.DEVELOPMENT_SETTINGS_ENABLED, 0) == 1
            o["adb"] = Settings.Global.getInt(ctx.contentResolver, Settings.Global.ADB_ENABLED, 0) == 1
        } catch (e: Exception) { }
        try {
            o["installUnknown"] = ctx.packageManager.canRequestPackageInstalls()
        } catch (e: Exception) { }
        try {
            val dpm = ctx.getSystemService(Context.DEVICE_POLICY_SERVICE) as android.app.admin.DevicePolicyManager
            val st = dpm.storageEncryptionStatus
            o["encrypted"] = st == android.app.admin.DevicePolicyManager.ENCRYPTION_STATUS_ACTIVE ||
                st == android.app.admin.DevicePolicyManager.ENCRYPTION_STATUS_ACTIVE_PER_USER ||
                st == android.app.admin.DevicePolicyManager.ENCRYPTION_STATUS_ACTIVE_DEFAULT_KEY
        } catch (e: Exception) { }
        val su = listOf("/system/bin/su", "/system/xbin/su", "/sbin/su", "/su/bin/su", "/data/local/xbin/su")
        o["root"] = su.any { File(it).exists() }
        return o
    }

    fun optInfo(ctx: Context): Map<String, Any?> {
        val o = HashMap<String, Any?>()
        val pm = ctx.getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
        o["ignoringBattery"] = try { pm.isIgnoringBatteryOptimizations(ctx.packageName) } catch (e: Exception) { false }
        o["powerSave"] = pm.isPowerSaveMode
        o["cacheBytes"] = dirSize(ctx.cacheDir) + dirSize(ctx.externalCacheDir)
        return o
    }

    /** Apaga o cache do OpenEXE (não toca em notas, vault, imagens da área de transferência nem atualização). */
    fun clearCache(ctx: Context): Long = dirClear(ctx.cacheDir) + dirClear(ctx.externalCacheDir)
}
