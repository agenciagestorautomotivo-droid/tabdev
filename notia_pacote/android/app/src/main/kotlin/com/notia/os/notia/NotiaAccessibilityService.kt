package com.notia.os.notia

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Color
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.Rect
import android.os.Bundle
import android.view.Gravity
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.LinearLayout
import android.widget.TextView
import org.json.JSONArray
import org.json.JSONObject

/**
 * Permite ao Notia ver e operar outros apps como uma pessoa faria: ler a tela,
 * tocar, digitar, rolar e voltar. Só age quando o agente do Notia pede, e só depois
 * de você ativar o serviço em Configurações > Acessibilidade.
 */
class NotiaAccessibilityService : AccessibilityService() {

    companion object {
        @Volatile
        var instance: NotiaAccessibilityService? = null
    }

    private val nodes = ArrayList<AccessibilityNodeInfo>()
    private var overlay: LinearLayout? = null
    private var overlayText: TextView? = null

    @Volatile
    var currentPackage: String = ""

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onUnbind(intent: android.content.Intent?): Boolean {
        instance = null
        hideOverlay()
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        instance = null
        hideOverlay()
        super.onDestroy()
    }

    override fun onInterrupt() {}

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            val p = event.packageName?.toString()
            if (!p.isNullOrEmpty()) currentPackage = p
        }
    }

    // ---------- Leitura da tela ----------

    /** Lista compacta dos elementos visíveis. Cada item recebe um índice (id) usado nas ações. */
    fun snapshot(): String {
        nodes.clear()
        val out = JSONArray()
        val res = JSONObject()
        val root = rootInActiveWindow
        if (root == null) {
            res.put("pkg", "")
            res.put("nodes", out)
            return res.toString()
        }
        res.put("pkg", root.packageName?.toString() ?: "")
        walk(root, out, 0)
        res.put("nodes", out)
        return res.toString()
    }

    private fun kindOf(n: AccessibilityNodeInfo): String {
        val cls = n.className?.toString() ?: ""
        return when {
            n.isEditable || cls.endsWith("EditText") -> "input"
            n.isCheckable || cls.endsWith("Switch") || cls.endsWith("CheckBox") ||
                cls.endsWith("RadioButton") || cls.endsWith("ToggleButton") -> "check"
            cls.endsWith("ImageView") || cls.endsWith("ImageButton") ->
                if (n.isClickable) "btn" else "img"
            n.isClickable || cls.endsWith("Button") -> "btn"
            else -> "txt"
        }
    }

    private fun walk(n: AccessibilityNodeInfo?, out: JSONArray, depth: Int) {
        if (n == null || depth > 40 || nodes.size >= 90) return
        if (!n.isVisibleToUser) return
        val r = Rect()
        n.getBoundsInScreen(r)
        val text = (n.text?.toString()?.takeIf { it.isNotBlank() }
            ?: n.contentDescription?.toString()?.takeIf { it.isNotBlank() }
            ?: n.hintText?.toString()?.takeIf { it.isNotBlank() }
            ?: "").trim().replace("\n", " ")
        val useful = text.isNotEmpty() || n.isClickable || n.isEditable ||
            n.isScrollable || n.isCheckable
        if (useful && r.width() > 0 && r.height() > 0) {
            val o = JSONObject()
            o.put("i", nodes.size)
            o.put("k", kindOf(n))
            o.put("x", if (text.length > 60) text.substring(0, 60) else text)
            if (n.isScrollable) o.put("s", 1)
            if (n.isCheckable) o.put("on", if (n.isChecked) 1 else 0)
            if (n.isPassword) o.put("pw", 1)
            nodes.add(n)
            out.put(o)
        }
        for (i in 0 until n.childCount) walk(n.getChild(i), out, depth + 1)
    }

    // ---------- Ações ----------

    fun clickIndex(i: Int): Boolean {
        val n = nodes.getOrNull(i) ?: return false
        n.refresh()
        var cur: AccessibilityNodeInfo? = n
        var depth = 0
        while (cur != null && depth < 6) {
            if (cur.isClickable && cur.performAction(AccessibilityNodeInfo.ACTION_CLICK)) return true
            cur = cur.parent
            depth++
        }
        val r = Rect()
        n.getBoundsInScreen(r)
        return tap(r.centerX().toFloat(), r.centerY().toFloat())
    }

    fun setText(i: Int, text: String): Boolean {
        val n = nodes.getOrNull(i) ?: return false
        n.refresh()
        if (n.isPassword) return false
        n.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
        n.performAction(AccessibilityNodeInfo.ACTION_CLICK)
        val args = Bundle()
        args.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        return n.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
    }

    fun scroll(down: Boolean): Boolean {
        var best: AccessibilityNodeInfo? = null
        var bestArea = -1
        val r = Rect()
        for (n in nodes) {
            if (!n.isScrollable) continue
            n.getBoundsInScreen(r)
            val a = r.width() * r.height()
            if (a > bestArea) {
                bestArea = a
                best = n
            }
        }
        if (best != null) {
            best.refresh()
            val act = if (down) AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
            else AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD
            if (best.performAction(act)) return true
        }
        val dm = resources.displayMetrics
        val x = dm.widthPixels / 2f
        val from = dm.heightPixels * (if (down) 0.7f else 0.3f)
        val to = dm.heightPixels * (if (down) 0.3f else 0.7f)
        return swipe(x, from, x, to)
    }

    private fun tap(x: Float, y: Float): Boolean {
        val p = Path().apply { moveTo(x, y) }
        val g = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(p, 0, 60)).build()
        return dispatchGesture(g, null, null)
    }

    private fun swipe(x1: Float, y1: Float, x2: Float, y2: Float): Boolean {
        val p = Path().apply {
            moveTo(x1, y1)
            lineTo(x2, y2)
        }
        val g = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(p, 0, 350)).build()
        return dispatchGesture(g, null, null)
    }

    fun back(): Boolean = performGlobalAction(GLOBAL_ACTION_BACK)
    fun home(): Boolean = performGlobalAction(GLOBAL_ACTION_HOME)

    // ---------- Faixa de status com botão PARAR (visível por cima de qualquer app) ----------

    fun showOverlay(text: String) {
        try {
            if (overlay == null) {
                val d = resources.displayMetrics.density
                val box = LinearLayout(this)
                box.orientation = LinearLayout.HORIZONTAL
                box.setBackgroundColor(Color.parseColor("#E60A0A0C"))
                box.setPadding((12 * d).toInt(), (6 * d).toInt(), (12 * d).toInt(), (6 * d).toInt())
                val tv = TextView(this)
                tv.setTextColor(Color.parseColor("#5EEAD4"))
                tv.textSize = 13f
                val stop = TextView(this)
                stop.text = "  PARAR"
                stop.setTextColor(Color.parseColor("#FCA5A5"))
                stop.textSize = 14f
                stop.setPadding((16 * d).toInt(), (6 * d).toInt(), (8 * d).toInt(), (6 * d).toInt())
                stop.setOnClickListener {
                    NotiaBridge.emit(mapOf("type" to "agent_stop"))
                    tv.text = "Parando…"
                }
                box.addView(tv)
                box.addView(stop)
                val lp = WindowManager.LayoutParams(
                    WindowManager.LayoutParams.WRAP_CONTENT,
                    WindowManager.LayoutParams.WRAP_CONTENT,
                    WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
                    PixelFormat.TRANSLUCENT
                )
                lp.gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
                lp.y = (8 * d).toInt()
                (getSystemService(WINDOW_SERVICE) as WindowManager).addView(box, lp)
                overlay = box
                overlayText = tv
            }
            overlayText?.text = text
        } catch (_: Exception) {
        }
    }

    private var confirmBox: LinearLayout? = null

    /** Pergunta SIM/NÃO por cima do app. A resposta volta ao Flutter como evento agent_confirm. */
    fun showConfirm(msg: String) {
        hideConfirm()
        try {
            val d = resources.displayMetrics.density
            val pad = (16 * d).toInt()
            val box = LinearLayout(this)
            box.orientation = LinearLayout.VERTICAL
            box.setBackgroundColor(Color.parseColor("#F00A0A0C"))
            box.setPadding(pad, pad, pad, pad)
            val tv = TextView(this)
            tv.text = msg
            tv.setTextColor(Color.parseColor("#FCD34D"))
            tv.textSize = 16f
            tv.maxWidth = (resources.displayMetrics.widthPixels * 0.6f).toInt()
            val row = LinearLayout(this)
            row.orientation = LinearLayout.HORIZONTAL
            row.gravity = Gravity.END
            row.setPadding(0, pad, 0, 0)
            fun button(label: String, color: String, ok: Boolean): TextView {
                val b = TextView(this)
                b.text = label
                b.textSize = 16f
                b.setTextColor(Color.parseColor(color))
                b.setPadding(pad * 2, pad / 2, pad * 2, pad / 2)
                b.setOnClickListener {
                    NotiaBridge.emit(mapOf("type" to "agent_confirm", "ok" to ok))
                    hideConfirm()
                }
                return b
            }
            row.addView(button("NÃO", "#FCA5A5", false))
            row.addView(button("SIM", "#5EEAD4", true))
            box.addView(tv)
            box.addView(row)
            val lp = WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
                PixelFormat.TRANSLUCENT
            )
            lp.gravity = Gravity.CENTER
            (getSystemService(WINDOW_SERVICE) as WindowManager).addView(box, lp)
            confirmBox = box
        } catch (_: Exception) {
            NotiaBridge.emit(mapOf("type" to "agent_confirm", "ok" to false))
        }
    }

    fun hideConfirm() {
        try {
            confirmBox?.let { (getSystemService(WINDOW_SERVICE) as WindowManager).removeView(it) }
        } catch (_: Exception) {
        }
        confirmBox = null
    }

    fun hideOverlay() {
        hideConfirm()
        try {
            overlay?.let { (getSystemService(WINDOW_SERVICE) as WindowManager).removeView(it) }
        } catch (_: Exception) {
        }
        overlay = null
        overlayText = null
    }
}
