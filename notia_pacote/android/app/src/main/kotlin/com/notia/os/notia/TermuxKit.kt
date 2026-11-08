package com.notia.os.notia

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

/** Ponte com o Termux: roda comandos no terminal Linux do tablet e devolve a saída. */
object TermuxKit {
    const val PERM = "com.termux.permission.RUN_COMMAND"
    private const val HOME = "/data/data/com.termux/files/home"
    private const val BASH = "/data/data/com.termux/files/usr/bin/bash"

    fun installed(ctx: Context): Boolean = try {
        ctx.packageManager.getPackageInfo("com.termux", 0)
        true
    } catch (e: Exception) {
        false
    }

    fun hasPermission(ctx: Context): Boolean =
        ContextCompat.checkSelfPermission(ctx, PERM) == PackageManager.PERMISSION_GRANTED

    fun requestPermission(act: Activity) {
        ActivityCompat.requestPermissions(act, arrayOf(PERM), 4711)
    }

    fun open(ctx: Context): Boolean {
        val i = ctx.packageManager.getLaunchIntentForPackage("com.termux") ?: return false
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        ctx.startActivity(i)
        return true
    }

    /** Devolve "ok" se o comando foi entregue ao Termux; o resultado chega depois pelo evento "termux". */
    fun run(ctx: Context, id: String, cmd: String, workdir: String?): String {
        if (!installed(ctx)) return "sem_termux"
        if (!hasPermission(ctx)) return "sem_permissao"
        return try {
            val back = Intent(ctx, TermuxResultReceiver::class.java).putExtra("id", id)
            val flags = PendingIntent.FLAG_ONE_SHOT or
                (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
            val pi = PendingIntent.getBroadcast(ctx, (id.hashCode() and 0x7fffffff), back, flags)
            val i = Intent("com.termux.RUN_COMMAND")
            i.setClassName("com.termux", "com.termux.app.RunCommandService")
            i.putExtra("com.termux.RUN_COMMAND_PATH", BASH)
            i.putExtra("com.termux.RUN_COMMAND_ARGUMENTS", arrayOf("-lc", cmd))
            i.putExtra("com.termux.RUN_COMMAND_WORKDIR", if (workdir.isNullOrBlank()) HOME else workdir)
            i.putExtra("com.termux.RUN_COMMAND_BACKGROUND", true)
            i.putExtra("com.termux.RUN_COMMAND_PENDING_INTENT", pi)
            if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(i) else ctx.startService(i)
            "ok"
        } catch (e: SecurityException) {
            "sem_permissao"
        } catch (e: Exception) {
            "erro:" + (e.message ?: "")
        }
    }
}

class TermuxResultReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        val id = intent.getStringExtra("id") ?: return
        val b = intent.getBundleExtra("result")
        NotiaBridge.emit(
            mapOf(
                "type" to "termux",
                "id" to id,
                "stdout" to (b?.getString("stdout") ?: ""),
                "stderr" to (b?.getString("stderr") ?: ""),
                "exit" to (b?.getInt("exitCode", -1) ?: -1),
                "err" to (b?.getInt("err", -1) ?: -1),
                "errmsg" to (b?.getString("errmsg") ?: "")
            )
        )
    }
}
