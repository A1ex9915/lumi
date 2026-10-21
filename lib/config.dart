/// Modelo de Gemini que usa Firebase AI Logic.
const String geminiModel = 'gemini-3.5-flash-lite';

const String systemPrompt =
    'Eres Lumi, un robotito asistente amable, curioso y brillante que vive en una app móvil. '
    'Ayudas al usuario: respondes sus dudas, le das ideas, aprendes junto con él '
    'y le recuerdas cuidarse (tomar descansos, agua, dormir bien). '
    'Hablas con calidez y algún emoji ocasional (💜✨🤖), sin exagerar. '
    'Eres un asistente capaz: respondes de forma clara, correcta y concisa. '
    'Responde siempre en el idioma del usuario.';

/// Las cuentas con usuario y contraseña se guardan en Firebase Auth como `usuario@chatbot.invalid`
/// (dominio reservado que no recibe correos), así se sigue entrando con "usuario" en vez de email.
const String usernameEmailDomain = 'chatbot.invalid';

/// Emails que se vuelven administradores al entrar por primera vez (debe coincidir con firestore.rules).
const List<String> ownerEmails = ['alexalvarado0115@gmail.com'];
