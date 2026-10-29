# Historial de cambios

Todas las versiones de **Lumi** y lo que cambió en cada una.
El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y las versiones usan
[SemVer](https://semver.org/lang/es/): `MAYOR.MENOR.PARCHE`.

Descarga cualquier versión en [**Releases**](https://github.com/A1ex9915/lumi/releases).

---

## 💬 Observaciones de los testers

Cada comentario de un tester se registra como un *Issue* (con los formularios del README). Cuando se corrige,
el commit lo menciona (`fix: … (#12)`) y el Issue se cierra solo al unir el cambio.

| # | Observación del tester | Cambio realizado | Versión |
|:---:|---|---|:---:|
| — | *Aún no hay observaciones registradas.* [Deja la tuya →](https://github.com/A1ex9915/lumi/issues/new/choose) | — | — |

---

## [1.2.0] - 2026-10-29

### Añadido
- **Registro manual con correo**, aparte de *Continuar con Google*: nombre, correo, contraseña y confirmación.
- **Verificación del correo**: se envía un enlace y la cuenta no se puede usar hasta tocarlo
  (pantalla con *Ya lo verifiqué* y *Reenviar correo*).
- **Contraseña segura**: mínimo 8 caracteres y al menos un carácter especial, con lista de requisitos en vivo.
- Inicio de sesión con **correo o usuario**.
- Pruebas automáticas de las validaciones y del formulario de registro.

### Cambiado
- La regla de contraseña también se aplica al crear usuarios desde el panel de administración.

### Seguridad
- Las reglas de Firestore bloquean el acceso a los datos de las cuentas con correo sin verificar.

## [1.1.0] - 2026-10-26

### Añadido
- **Comentarios de testers dentro de la app** (menú ☰): calificación con estrellas, tipo
  (error, idea, me gusta), captura opcional, 👍 y respuestas del administrador en tiempo real.
- **Comentarios de testers en GitHub**: formularios para reportar errores, proponer ideas y dejar una opinión,
  con botones y contadores en vivo en el README.
- Botón de descarga directa de la última versión en el README.

### Cambiado
- Nuevo diseño del README con logo, captura de la app y galería de Lumi.

## [1.0.0] - 2026-10-21

Primera versión publicada para testers.

### Añadido
- Chat con IA (Gemini mediante Firebase AI Logic) con respuestas que se escriben palabra por palabra,
  botón para detener y para pedir otra respuesta.
- Envío de fotos desde la cámara o la galería para que Lumi las analice.
- Reacciones ❤️, respuestas rápidas y expresiones animadas de Lumi.
- Inicio de sesión con Google y con usuario y contraseña (Firebase Authentication).
- Historial de conversaciones en Cloud Firestore, visible también sin conexión.
- Panel de administración: crear usuarios, cambiar roles y bloquear cuentas.
- Diseño de marca Lumi, modo claro/oscuro y soporte para vertical y horizontal.

### Corregido durante las pruebas internas (antes de publicar)
| Observación | Corrección |
|---|---|
| La respuesta de la IA aparecía de golpe, por párrafos | Ahora se escribe palabra por palabra a ritmo constante |
| En horizontal con el teclado abierto, la caja de texto se desbordaba ("BOTTOM OVERFLOWED") | Modo compacto y caja de texto que nunca supera el alto disponible |
| En horizontal, el menú lateral se cortaba y no se podía cerrar sesión | El menú se vuelve una lista desplazable cuando hay poca altura |
| El logo se veía con un recuadro de fondo sobre la ilustración | Se quitó el fondo del logo (transparente) |
| La compilación se cerraba por falta de memoria en equipos con poca RAM | Se ajustó la memoria de Gradle |

[1.2.0]: https://github.com/A1ex9915/lumi/releases/tag/v1.2.0
[1.1.0]: https://github.com/A1ex9915/lumi/releases/tag/v1.1.0
[1.0.0]: https://github.com/A1ex9915/lumi/releases/tag/v1.0.0
