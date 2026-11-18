package com.example.presupuesto_familiar

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Bandeja de notificaciones guardadas por EscuchaNotificaciones (ver ServicioNotificaciones)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "presupuesto_familiar/notificaciones")
            .setMethodCallHandler { llamada, resultado ->
                when (llamada.method) {
                    "configurar" -> {
                        BandejaNotificaciones.configurar(
                            this,
                            llamada.argument<Boolean>("activo") ?: false,
                            llamada.argument<List<String>>("paquetes") ?: emptyList(),
                        )
                        resultado.success(null)
                    }
                    "recoger" -> resultado.success(BandejaNotificaciones.recoger(this))
                    "reconectar" -> {
                        EscuchaNotificaciones.pedirReconexion(this)
                        resultado.success(null)
                    }
                    "bateriaSinRestricciones" -> resultado.success(bateriaSinRestricciones())
                    "pedirBateriaSinRestricciones" -> {
                        pedirBateriaSinRestricciones()
                        resultado.success(null)
                    }
                    else -> resultado.notImplemented()
                }
            }
    }

    // Sin restricciones, Android no corta el servicio de notificaciones para ahorrar batería
    private fun bateriaSinRestricciones(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val energia = getSystemService(POWER_SERVICE) as PowerManager
        return energia.isIgnoringBatteryOptimizations(packageName)
    }

    // Abre la lista de optimización de batería de Android: el diálogo directo exige un permiso que
    // Google Play no admite en esta app. Si el móvil no tiene esa lista, abre la ficha de la app.
    private fun pedirBateriaSinRestricciones() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || bateriaSinRestricciones()) return
        try {
            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
        } catch (_: Exception) {
            try {
                startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
            } catch (_: Exception) {
            }
        }
    }
}
