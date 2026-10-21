# Lumi 🤖💜

**Lumi** es un asistente de chat con inteligencia artificial para Android: responde tus dudas, te da ideas,
analiza tus fotos y te recuerda cuidarte.

Hecho con **Flutter + Firebase + Gemini**. No necesita servidor propio: la app habla directo con Firebase.

## 📲 Instalar en tu teléfono

1. Descarga **`lumi.apk`** desde la sección [**Releases**](../../releases) de este repositorio.
2. Ábrelo en tu teléfono Android. Si te lo pide, permite **"Instalar apps de fuentes desconocidas"**
   para tu navegador o administrador de archivos.
3. Abre **Lumi** y entra con **Continuar con Google** o crea una cuenta con usuario y contraseña.

> Requiere Android 7.0 o superior y conexión a internet para las respuestas de la IA.

## ✨ Funciones

- Chat con IA (Gemini) con respuestas que se escriben palabra por palabra, botón para detener y regenerar.
- 📸 Envía fotos desde la cámara o la galería y Lumi te dice qué ve.
- ❤️ Reacciones, respuestas rápidas y expresiones animadas de Lumi.
- Historial de conversaciones en la nube (se ve también sin conexión).
- Inicio de sesión con Google o usuario/contraseña.
- Panel de administración: crear usuarios, cambiar roles y bloquear cuentas.
- Modo claro/oscuro y diseño adaptado a vertical y horizontal.

## 🏗️ Arquitectura

| Pieza | Servicio |
|---|---|
| Inicio de sesión | Firebase Authentication (Google y usuario/contraseña) |
| Usuarios, conversaciones y fotos | Cloud Firestore |
| Respuestas de la IA (streaming, fotos) | Firebase AI Logic → Gemini |
| Seguridad | [`firestore.rules`](firestore.rules): cada quien solo ve sus chats |

```
lib/
├── main.dart            Arranque y cambio login/chat
├── config.dart          Modelo de Gemini, personalidad de Lumi, administradores
├── theme.dart           Colores, fuentes e imágenes de la marca
├── api_service.dart     Firebase Auth + Firestore + Gemini y estado de la sesión
├── models.dart
└── screens/
    ├── login_screen.dart    Login, registro y Google
    ├── chat_screen.dart     Chat, fotos, reacciones, historial
    └── users_screen.dart    Administración de usuarios
assets/lumi/             Logo, ícono e ilustraciones de Lumi
firestore.rules          Reglas de seguridad de Firestore
server/                  Backend antiguo (Express + SQLite), ya no se usa
docs/                    Documento de arquitectura del proyecto
```

## 🛠️ Compilar desde el código

Requisitos: [Flutter](https://flutter.dev) y el [CLI de Firebase](https://firebase.google.com/docs/cli).

1. **Configuración de Firebase** (no está en el repositorio porque contiene la API key):
   ```bash
   firebase apps:sdkconfig ANDROID 1:349783982260:android:23c20d1560b7f4e988d7e1 \
     --project gen-lang-client-0815449786 --out android/app/google-services.json
   ```
   Si usas tu propio proyecto de Firebase, registra la app Android `com.example.chatbotmovil`,
   activa Authentication (Google y correo), Firestore y AI Logic (Gemini Developer API),
   y publica las reglas con `firebase deploy --only firestore:rules`.

2. **Ejecutar en un teléfono conectado:**
   ```bash
   flutter pub get
   flutter run
   ```

3. **APK de producción:** crea `android/key.properties` (no se sube a git) con tu llave de firma:
   ```properties
   storePassword=...
   keyPassword=...
   keyAlias=...
   storeFile=C:/ruta/a/tu-llave.jks
   ```
   y compila con `flutter build apk --release`. Sin `key.properties` se firma con la llave de depuración.
   Para que **Continuar con Google** funcione, registra en Firebase la huella SHA-1 de la llave con la que firmas.

## 👩‍💼 Administradores

Los correos de `ownerEmails` (en `lib/config.dart` y `firestore.rules`) se vuelven administradores al
entrar con Google por primera vez. Un administrador puede crear usuarios, cambiar nombre/rol y bloquear cuentas.
