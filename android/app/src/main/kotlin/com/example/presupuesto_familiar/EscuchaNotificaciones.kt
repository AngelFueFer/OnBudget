package com.example.presupuesto_familiar

import android.app.Notification
import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import notification.listener.service.NotificationListener
import org.json.JSONArray
import org.json.JSONObject

// Servicio de lectura de notificaciones. Android lo mantiene vivo aunque la app esté cerrada:
// guarda las notificaciones de las apps de pago en una bandeja y la app las recoge al abrirse.
// Mientras la app está abierta, el plugin además le avisa al momento (super.onNotificationPosted).
class EscuchaNotificaciones : NotificationListener() {
    override fun onNotificationPosted(notificacion: StatusBarNotification) {
        // Primero se guarda: el aviso del plugin hace que la app recoja la bandeja
        BandejaNotificaciones.guardar(this, notificacion)
        super.onNotificationPosted(notificacion)
    }

    // El plugin pide reconectar su propia clase, que no está declarada en el manifiesto:
    // sin esto, si Android corta el servicio, la lectura se para hasta reiniciar el móvil
    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        pedirReconexion(this)
    }

    companion object {
        fun pedirReconexion(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
            try {
                NotificationListenerService.requestRebind(ComponentName(context, EscuchaNotificaciones::class.java))
            } catch (_: Exception) {
                // Sin permiso concedido no se puede reconectar; no pasa nada
            }
        }
    }
}

// Notificaciones pendientes de procesar. Solo las de las apps que la app ha pedido escuchar,
// y solo hasta que la app las recoge (entonces se borran).
object BandejaNotificaciones {
    private const val PREFS = "escucha_notificaciones"
    private const val ACTIVO = "activo"
    private const val PAQUETES = "paquetes"
    private const val PENDIENTES = "pendientes"
    private const val MAX_PENDIENTES = 100

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    // Lo llama la app al activar/desactivar la lectura y al arrancar
    fun configurar(context: Context, activo: Boolean, paquetes: List<String>) {
        val editor = prefs(context).edit()
            .putBoolean(ACTIVO, activo)
            .putStringSet(PAQUETES, paquetes.toSet())
        if (!activo) editor.remove(PENDIENTES)
        editor.apply()
    }

    @Synchronized
    fun guardar(context: Context, sbn: StatusBarNotification) {
        try {
            val prefs = prefs(context)
            if (!prefs.getBoolean(ACTIVO, false)) return
            if (sbn.packageName !in (prefs.getStringSet(PAQUETES, emptySet()) ?: emptySet())) return

            val notificacion = sbn.notification
            if (notificacion.flags and (Notification.FLAG_ONGOING_EVENT or Notification.FLAG_GROUP_SUMMARY) != 0) return
            val extras = notificacion.extras ?: return
            val titulo = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
            // El texto largo suele traer el comercio completo
            val texto = (extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
                ?: extras.getCharSequence(Notification.EXTRA_TEXT))?.toString()
            if (titulo.isNullOrBlank() && texto.isNullOrBlank()) return

            val pendientes = JSONArray(prefs.getString(PENDIENTES, "[]"))
            pendientes.put(JSONObject().apply {
                put("paquete", sbn.packageName)
                put("titulo", titulo?.take(100))
                put("texto", texto?.take(500))
                put("fecha", sbn.postTime)
            })
            // Si la app lleva mucho sin abrirse, se quedan las más recientes
            val desde = maxOf(0, pendientes.length() - MAX_PENDIENTES)
            val recortadas = JSONArray()
            for (i in desde until pendientes.length()) recortadas.put(pendientes.get(i))
            prefs.edit().putString(PENDIENTES, recortadas.toString()).commit()
        } catch (_: Exception) {
            // Una notificación rara no debe tumbar el servicio
        }
    }

    // Devuelve las pendientes y vacía la bandeja
    @Synchronized
    fun recoger(context: Context): List<Map<String, Any?>> {
        val prefs = prefs(context)
        val pendientes = JSONArray(prefs.getString(PENDIENTES, "[]"))
        prefs.edit().remove(PENDIENTES).commit()
        return (0 until pendientes.length()).map { i ->
            val n = pendientes.getJSONObject(i)
            mapOf(
                "paquete" to n.optString("paquete"),
                "titulo" to (if (n.isNull("titulo")) null else n.optString("titulo")),
                "texto" to (if (n.isNull("texto")) null else n.optString("texto")),
                "fecha" to n.optLong("fecha"),
            )
        }
    }
}
