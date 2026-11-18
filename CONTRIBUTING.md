# Cómo contribuir a On Budget

¡Gracias por querer ayudar! On Budget es una app de presupuesto doméstico **libre (AGPL-3.0)**, sin cuentas, sin anuncios y con los datos en el dispositivo.
Cualquier ayuda cuenta: probar, reportar fallos, traducir, añadir el formato de tu banco o programar.

> **English:** contributions in English are welcome too. Code, comments and commit messages in this repo are written in Spanish; we'll help you with that in review.

## Antes de empezar

- Lee el [código de conducta](CODE_OF_CONDUCT.md).
- Para fallos de seguridad **no abras un issue público**: mira [SECURITY.md](SECURITY.md).
- Para cambios grandes, abre antes un issue y cuéntanos la idea. Así nadie trabaja en balde.

## Principios que no se negocian

1. **Privacidad:** sin cuentas, sin servidor del desarrollador, sin anuncios, sin analítica ni SDK de rastreo. Los datos viven en el dispositivo (SQLite + SharedPreferences).
2. **Red solo opcional** y con la clave del propio usuario. Nada se conecta por defecto.
3. **Rápida:** apuntar un gasto en 3 toques.
4. **Cuatro idiomas:** todo texto visible va en `AppLocalizations` en español, inglés, francés y alemán.
5. **Tema claro y oscuro.** Usa los colores del tema (`Theme.of(context).colorScheme`), no colores fijos.

Un PR que rompa alguno de estos principios no se fusionará, aunque el código sea bueno.

## Preparar el entorno

```bash
git clone https://github.com/AngelFueFer/OnBudget.git
cd OnBudget
flutter pub get
flutter run
```

La versión de Flutter de referencia es la del workflow `.github/workflows/apk.yml`.
El servidor opcional de sincronización está en `servidor/` y tiene su propio [README](servidor/README.md).

## Convenciones del código

- **Todo en español:** nombres, comentarios y mensajes de commit. Comentarios breves que expliquen el *porqué*.
- **Sin cadenas mágicas:** usa `AppStrings`, `DBKeys`, `AppNumbers` y `AppColors` (`lib/constants/`).
- **Valores guardados nunca se traducen:** en la base de datos se guarda la clave, y se traduce al mostrarla.
- **Dinero en céntimos** (enteros), nunca `double`.
- **Migraciones SQLite seguras:** sube la versión de la base de datos y migra sin perder datos. El JSON guardado debe seguir leyéndose en versiones anteriores.
- **Estado:** `StatefulWidget` + `ValueNotifier`, sin gestores de estado externos.
- Los controladores de diálogos se liberan en el `dispose` del `State`.
- Los servicios tienen dependencias sustituibles para poder probarlos.
- **Tests en español** para toda lógica nueva (`test/`).
- No cambies el estilo gráfico (colores, tipografía, componentes) sin hablarlo antes en un issue.

## Cómo se trabaja

1. **Issue primero.** Fallos, bancos e ideas entran por [issues](https://github.com/AngelFueFer/OnBudget/issues/new/choose) con su plantilla.
   Los marcados `good first issue` son buenos para empezar. Comenta en el issue que te pones con él para no duplicar trabajo.
2. **Fork y rama.** Haz un fork, crea una rama desde `main` con un nombre corto: `fallo/importe-negativo`, `banco/openbank`, `idea/exportar-csv`, `traduccion/fr`.
3. **PR contra `main`.** Rellena la plantilla y enlaza el issue (`Cierra #123`). Si aún no está listo, ábrelo como borrador.
4. **Comprobaciones automáticas.** Cada PR pasa `flutter analyze` y `flutter test` (y los tests del servidor si tocas `servidor/`).
   La primera vez que contribuyes, un mantenedor tiene que aprobar que se ejecuten.
5. **Revisión.** GitHub pide la revisión a los mantenedores de [CODEOWNERS](.github/CODEOWNERS). Puede que pidamos cambios; es normal.
6. **Fusión.** Solo un mantenedor fusiona en `main`. Al fusionar se publica una versión nueva del APK.

Nadie sube directamente a `main`: todo cambio, también los del mantenedor, entra por PR.

## Quién decide

On Budget lo mantiene [@AngelFueFer](https://github.com/AngelFueFer), que tiene la última palabra sobre qué entra.
Las decisiones se discuten en abierto en los issues y en los PRs. Quien contribuya de forma constante y con buen criterio
puede pasar a ser mantenedor y revisar PRs de su parte (se añade a CODEOWNERS).

## Antes de abrir el PR

```bash
flutter analyze   # sin avisos
flutter test      # todo en verde
```

- Una rama por cambio y un PR pequeño y enfocado.
- Explica qué cambia, por qué y cómo lo has probado (rellena la plantilla).
- Si el cambio afecta a **datos guardados, privacidad o permisos de Android/iOS**, dilo claramente en el PR.
- Si añades textos visibles, incluye las cuatro traducciones.

## Añadir tu banco

Cada banco escribe sus notificaciones y extractos a su manera. Abre un issue con la plantilla **«Mi banco no se detecta»** y pega el
**formato** de la notificación o de una línea del extracto, cambiando importes, comercios, IBAN y dígitos de tarjeta por otros inventados.
**Nunca** pegues datos reales.

## Traducciones

Los textos están en `lib/l10n/traducciones/` (`es.dart`, `en.dart`, `fr.dart`, `de.dart`). Corregir una traducción es un PR perfecto para empezar.
Para un idioma nuevo, abre antes un issue.

## Licencia

Al contribuir aceptas que tu aportación se publique con la licencia del proyecto, [AGPL-3.0](LICENSE).
