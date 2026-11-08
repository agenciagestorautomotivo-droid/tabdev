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
}
