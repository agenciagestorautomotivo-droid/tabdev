package com.notia.os.notia

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/**
 * Ponte entre os serviços do Android (acessibilidade, notificações, atalho, compartilhar)
 * e o Flutter. Se o Flutter ainda não está ouvindo, os eventos ficam numa fila curta.
 */
object NotiaBridge {
    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private val pending = ArrayDeque<Map<String, Any?>>()

    fun emit(event: Map<String, Any?>) {
        main.post {
            val s = sink
            if (s != null) {
                s.success(event)
            } else {
                pending.addLast(event)
                while (pending.size > 50) pending.removeFirst()
            }
        }
    }

    fun attach(s: EventChannel.EventSink?) {
        sink = s
        if (s != null) {
            while (pending.isNotEmpty()) s.success(pending.removeFirst())
        }
    }
}
