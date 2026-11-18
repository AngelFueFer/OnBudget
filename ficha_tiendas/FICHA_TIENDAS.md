# Ficha para Google Play y App Store

> La versión actualizada (textos en 4 idiomas, Data safety y guía de prueba cerrada) está en `sitio_web/publicar.html`, publicada en https://angelfuefer.github.io/OnBudget/publicar.html. Este archivo queda como referencia para App Store.

Sustituye `[DOMINIO]`, `[TITULAR]` y `[EMAIL SOPORTE]` aquí y en `sitio_web/`.

## 0. Bloqueantes antes de subir nada

- [x] **Nombre definitivo**: On Budget.
- [x] **applicationId / Bundle ID**: `app.onbudget`.
- [x] ~~**Permiso `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`**~~ (quitado; la app abre la lista de batería) (`android/app/src/main/AndroidManifest.xml`): Google Play solo lo permite si la función principal no puede funcionar sin él; una app de presupuesto suele ser rechazada. Alternativa sin permiso: abrir `Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS` y que el usuario lo cambie a mano.
- [ ] **Aviso destacado para el acceso a notificaciones**: antes de pedir el permiso, una pantalla dentro de la app que diga qué se lee, para qué y que se queda en el móvil, con botón de aceptar/rechazar (política de Datos de usuario de Google Play).
- [ ] **Cuenta de Google Play personal nueva**: hay que hacer una prueba cerrada con **12 testers durante 14 días** antes de poder publicar en producción. Empieza cuanto antes.
- [ ] **Estado de "comerciante" (UE, DSA)**: ambas tiendas lo piden. Si te declaras comerciante, tu dirección y teléfono se muestran públicamente en la ficha.
- [ ] La versión de iOS no tiene detección por notificaciones: no la menciones en la ficha de App Store.

## 1. Textos

**Nombre** (máx. 30): `On Budget: Presupuesto familiar`

**Descripción breve — Google Play** (máx. 80):
> Controla gastos e ingresos de casa. Tus datos solo en tu móvil, sin anuncios.

**Subtítulo — App Store** (máx. 30):
> Gastos y ahorro del hogar

**Palabras clave — App Store** (máx. 100, separadas por comas, sin espacios):
> presupuesto,gastos,ahorro,finanzas,familia,hogar,dinero,control,economía,cuentas,tiquets,mensual

**Descripción completa** (máx. 4000; en App Store quita el bloque marcado como Android):

```
On Budget te ayuda a saber en qué se va el dinero de casa, sin complicaciones.

APUNTA EN SEGUNDOS
• Ingresos y gastos por categorías, con accesos rápidos.
• Adjunta la foto del tiquet a cada gasto.

TU PRESUPUESTO MENSUAL, CLARO
• Reparte el mes entre cuenta mensual y ahorro.
• Remanente y déficit calculados automáticamente.
• Gastos fijos, tarjetas y cuentas de ahorro en un mismo sitio.

IMPORTA TU BANCO
• Extractos en CSV y Norma 43.

[Solo Android]
DETECCIÓN DE PAGOS (OPCIONAL)
• Si la activas, la app te propone los pagos que te avisan tu banco, tu wallet o tu app de pago.
• Solo se guarda la tarjeta, el importe y el comercio; nunca el texto de la notificación.
[/Solo Android]

INVERSIONES
• Sigue tus inversiones y, si quieres, conecta cotizaciones con tu propia clave de EODHD.

PRIVACIDAD DE VERDAD
• Sin registro ni cuentas.
• Todos tus datos se guardan solo en tu dispositivo.
• Sin anuncios y sin rastreo.

Disponible en español, inglés, francés y alemán, con tema claro y oscuro.
```

Traduce también ficha y capturas a EN/FR/DE si publicas en esos países (la app ya está traducida).

## 2. URLs (Cloudflare Pages + dominio propio)

Cloudflare Pages quita el `.html` de las URLs automáticamente.

| Campo | URL |
|---|---|
| Sitio web / Marketing | `https://[DOMINIO]/` |
| Soporte | `https://[DOMINIO]/soporte` |
| Política de privacidad | `https://[DOMINIO]/privacidad` |
| Email de contacto | `[EMAIL SOPORTE]` (obligatorio en Play; se muestra público). De momento un Gmail dedicado a la app; más adelante se puede pasar a `soporte@[DOMINIO]` con Cloudflare Email Routing |

## 3. Icono y gráficos

| Recurso | Tienda | Tamaño | Notas |
|---|---|---|---|
| Icono | Google Play | 512×512 PNG | Usa `assets/branding/logo_cuadrado.png` redimensionado; Play redondea solo |
| Icono | App Store | 1024×1024 PNG | **Sin transparencia** ni esquinas redondeadas; ya lo genera `tool/generar_logo.py` en `ios/Runner/Assets.xcassets` |
| Gráfico de funciones | Google Play | 1024×500 PNG/JPG | Obligatorio. Logo + lema sobre el degradado verde |
| Capturas móvil | Google Play | 2–8, p. ej. 1080×1920 o 1080×2400 | |
| Capturas iPhone | App Store | 1–10, 1320×2868 o 1290×2796 (6,9") | Obligatorias |
| Capturas iPad | App Store | 2064×2752 (13") | Solo si la app admite iPad; si no, desactívalo en Xcode |

**Capturas propuestas** (con datos de ejemplo, nunca los tuyos reales), con un titular encima de cada una:

1. Pantalla principal con el anillo del mes — "Tu mes, de un vistazo"
2. Formulario de nuevo gasto — "Apunta un gasto en 3 toques"
3. Presupuesto Cuenta Mensual / Ahorro — "Sabe cuánto te queda y cuánto ahorras"
4. Importar extracto — "Importa tu banco (CSV y Norma 43)"
5. Pago detectado (solo Android) — "Tus pagos, propuestos solos"
6. Ajustes / privacidad — "Tus datos, solo en tu móvil"

Tip: activa el tema claro, idioma de la ficha y `flutter run` en un emulador Pixel / simulador iPhone 16 Pro Max para sacar las capturas al tamaño correcto.

## 4. Google Play — Seguridad de los datos (Data Safety)

Según el código actual: todo es local (SQLite + SharedPreferences) y la única llamada de red es a EODHD, desactivada por defecto y con la clave del propio usuario.

| Pregunta | Respuesta |
|---|---|
| ¿Recoge o comparte datos de usuario? | **Sí** (por la consulta opcional a EODHD; ver abajo) |
| ¿Datos cifrados en tránsito? | Sí (HTTPS) |
| ¿Se puede pedir el borrado? | Los datos están en el dispositivo; el usuario los borra desinstalando o borrando datos |
| Tipo de dato | **Información financiera → Otra información financiera** (identificadores ISIN/ticker de las inversiones consultadas) |
| ¿Recogido / compartido? | Recogido: sí. Compartido: no (envío iniciado por el usuario a un servicio que él configura) |
| ¿Procesado de forma efímera? | Sí |
| ¿Obligatorio u opcional? | Opcional |
| Finalidad | Funcionalidad de la app |

Lo que **no** hay que declarar como recogido: movimientos, extractos, fotos de tiquets y datos de notificaciones, porque nunca salen del dispositivo ("acceso solo en el dispositivo").

Otros formularios de Play Console: Clasificación de contenido (cuestionario IARC → resultado "Todos"), Público objetivo **18+** (evita requisitos de apps infantiles), Anuncios: **No**, Acceso a la app: no requiere inicio de sesión, App financiera: declara "gestión de presupuesto / finanzas personales, sin servicios financieros regulados".

## 5. App Store — Privacidad de la app

Recomendado: **"Datos no recogidos"**. Apple considera "recogido" lo que sale del dispositivo y se conserva más allá de lo necesario para atender la petición en tiempo real; la consulta a EODHD solo pide un precio con la clave del usuario.

Si prefieres ser conservador: **Información financiera → Otra información financiera**, uso *Funcionalidad de la app*, **no vinculada** a la identidad, **no usada para rastreo**.

Además: Manifiesto de privacidad (`PrivacyInfo.xcprivacy`) — revisa que `shared_preferences` y `path_provider` traen el suyo (las versiones actuales sí) y declara el motivo de acceso a `UserDefaults` (`CA92.1`) si Xcode lo avisa al subir.

## 6. Países y precio

**Recomendación: gratis, sin anuncios.**

- En Google Play, una app publicada como gratuita **no puede pasar a ser de pago** después. Si quieres monetizar, hazlo más adelante con una compra dentro de la app (p. ej. "Pro" para inversiones/importación), no cobrando la descarga.
- Una app de pago exige perfil de pagos, datos fiscales y cuenta bancaria en ambas tiendas.
- Coste de las cuentas de desarrollador: Google Play 25 US$ una vez; Apple 99 US$/año.

**Países:**

- Fase 1: **España** (Norma 43 y el catálogo de bancos son españoles; así recoges reseñas y fallos con menos ruido).
- Fase 2: países de los idiomas que ya tienes — México, Argentina, Colombia, Chile, Perú (ES); Reino Unido, Irlanda, EE. UU. (EN); Francia, Bélgica (FR); Alemania, Austria, Suiza (DE). Revisa antes que la importación CSV y la moneda funcionan bien fuera de España.
