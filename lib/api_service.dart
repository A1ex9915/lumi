import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_auth/firebase_auth.dart' hide User;
import 'package:firebase_auth/firebase_auth.dart' as fb show User;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'config.dart';
import 'models.dart';
import 'validators.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

/// Todo el backend vive en Firebase: Auth (sesión), Firestore (datos) y Firebase AI Logic (Gemini).
/// Esta clase guarda además el estado de la sesión (usuario actual).
class ApiService extends ChangeNotifier {
  ApiService._();
  static final ApiService instance = ApiService._();

  bool firebaseReady = false;
  User? _user;
  bool _googleInitialized = false;

  User? get currentUser => _user;
  bool get isLoggedIn => _user != null;

  /// Correo registrado que todavía no se ha verificado (la app muestra la pantalla de verificación).
  String? _pendingEmail;
  String? get pendingEmail => _pendingEmail;

  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _users => _db.collection('users');
  CollectionReference<Map<String, dynamic>> _conversations([String? uid]) =>
      _users.doc(uid ?? _auth.currentUser!.uid).collection('conversations');

  late final GenerativeModel _model = FirebaseAI.googleAI().generativeModel(
    model: geminiModel,
    systemInstruction: Content.text(systemPrompt),
  );

  // ---------- Sesión ----------

  Future<void> init() async {
    try {
      await Firebase.initializeApp();
      firebaseReady = true;
    } catch (e) {
      debugPrint('Firebase no disponible: $e');
      return;
    }
    // Los correos de verificación de Firebase llegan en español
    await _auth.setLanguageCode('es');
    // Firebase recuerda la sesión: si ya había alguien dentro, cargamos su perfil
    final current = _auth.currentUser;
    if (current != null) {
      if (_needsVerification(current)) {
        _pendingEmail = current.email;
        return;
      }
      try {
        await _loadProfile();
      } catch (_) {
        await logout();
      }
    }
  }

  /// Cuentas con correo real que aún no lo verificaron. Las de Google ya vienen verificadas y las de
  /// usuario (`usuario@chatbot.invalid`, creadas por el admin) no tienen un correo que verificar.
  bool _needsVerification(fb.User u) {
    final email = u.email;
    if (email == null || u.emailVerified) return false;
    if (email.toLowerCase().endsWith('@$usernameEmailDomain')) return false;
    return u.providerData.any((p) => p.providerId == 'password');
  }

  /// Entra con correo (o con usuario, para las cuentas creadas por el admin) y contraseña.
  Future<void> login(String emailOrUsername, String password) async {
    final cred = await _guardAuth(
      () => _auth.signInWithEmailAndPassword(email: _emailFor(emailOrUsername), password: password),
    );
    if (_needsVerification(cred.user!)) {
      _pendingEmail = cred.user!.email;
      notifyListeners();
      return;
    }
    await _loadProfile();
  }

  /// Registro manual con correo: crea la cuenta y envía el correo de verificación.
  /// La cuenta no se puede usar hasta que la persona toque el enlace del correo.
  Future<void> registerWithEmail(String name, String email, String password) async {
    final cleanEmail = email.trim().toLowerCase();
    final error = validateEmail(cleanEmail) ?? validatePassword(password);
    if (error != null) throw ApiException(error);

    final cred = await _guardAuth(() => _auth.createUserWithEmailAndPassword(email: cleanEmail, password: password));
    final local = cleanEmail.split('@').first;
    await _users
        .doc(cred.user!.uid)
        .set(
          _newProfile(
            name: name.trim(),
            username: local.length > 40 ? local.substring(0, 40) : local,
            email: cleanEmail,
            provider: 'password',
          ),
        );
    await cred.user!.sendEmailVerification();
    _pendingEmail = cleanEmail;
    notifyListeners();
  }

  /// Comprueba si ya se tocó el enlace del correo. Si sí, entra a la app.
  Future<bool> checkEmailVerified() async {
    final u = _auth.currentUser;
    if (u == null) return false;
    await u.reload();
    final fresh = _auth.currentUser!;
    if (!fresh.emailVerified) return false;
    // Token nuevo para que las reglas de Firestore vean el correo como verificado
    await fresh.getIdToken(true);
    _pendingEmail = null;
    await _loadProfile();
    return true;
  }

  Future<void> resendVerificationEmail() async {
    final u = _auth.currentUser;
    if (u == null) return;
    await _guardAuth(() => u.sendEmailVerification());
  }

  /// Inicia sesión con Google. Devuelve false si el usuario cerró el selector de cuentas.
  Future<bool> loginWithGoogle() async {
    try {
      if (!_googleInitialized) {
        await GoogleSignIn.instance.initialize();
        _googleInitialized = true;
      }
      final account = await GoogleSignIn.instance.authenticate();
      final credential = GoogleAuthProvider.credential(idToken: account.authentication.idToken);
      final result = await _guardAuth(() => _auth.signInWithCredential(credential));

      // Primera vez: se crea su perfil
      final ref = _users.doc(result.user!.uid);
      if (!(await ref.get()).exists) {
        final email = result.user!.email;
        await ref.set(
          _newProfile(
            name: result.user!.displayName ?? email?.split('@').first ?? 'Usuario',
            username: (email?.split('@').first ?? 'usuario').toLowerCase(),
            email: email,
            provider: 'google',
            role: ownerEmails.contains(email) ? 'admin' : 'user',
          ),
        );
      }
      await _loadProfile();
      return true;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return false;
      throw ApiException('Error de Google: ${e.description ?? e.code.name}');
    }
  }

  Future<void> logout() async {
    _user = null;
    _pendingEmail = null;
    notifyListeners();
    await _auth.signOut();
    if (_googleInitialized) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
  }

  Future<void> _loadProfile() async {
    final doc = await _users.doc(_auth.currentUser!.uid).get();
    if (!doc.exists) {
      await _auth.signOut();
      throw ApiException('Tu cuenta no tiene perfil. Regístrate de nuevo o contacta al administrador.');
    }
    final user = User.fromDoc(doc);
    if (user.disabled) {
      await _auth.signOut();
      throw ApiException('Tu cuenta está bloqueada. Contacta al administrador.');
    }
    _user = user;
    notifyListeners();
  }

  String _emailFor(String username) {
    final u = username.trim().toLowerCase();
    return u.contains('@') ? u : '$u@$usernameEmailDomain';
  }

  Map<String, dynamic> _newProfile({
    required String name,
    required String username,
    required String provider,
    String? email,
    String role = 'user',
  }) => {
    'name': name,
    'username': username,
    'email': email,
    'provider': provider,
    'role': role,
    'disabled': false,
    'createdAt': FieldValue.serverTimestamp(),
  };

  /// Traduce los errores de Firebase Auth a mensajes en español.
  Future<T> _guardAuth<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseAuthException catch (e) {
      throw ApiException(switch (e.code) {
        'invalid-credential' || 'wrong-password' || 'user-not-found' => 'Correo, usuario o contraseña incorrectos',
        'invalid-email' => 'Ese correo no es válido',
        'email-already-in-use' => 'Ya existe una cuenta con ese correo o usuario. Inicia sesión.',
        'weak-password' => 'La contraseña es demasiado débil',
        'user-disabled' => 'Tu cuenta está deshabilitada',
        'too-many-requests' => 'Demasiados intentos. Espera un momento.',
        'network-request-failed' => 'Sin conexión a internet',
        _ => 'Error de autenticación: ${e.message ?? e.code}',
      });
    }
  }

  // ---------- Conversaciones ----------

  Future<List<Conversation>> getConversations() async {
    final snap = await _conversations().orderBy('updatedAt', descending: true).get();
    return snap.docs.map(Conversation.fromDoc).toList();
  }

  /// Reserva un id; la conversación se guarda al recibir la primera respuesta.
  Conversation newConversation() => Conversation(id: _conversations().doc().id, title: 'Nueva conversación');

  Future<void> deleteConversation(String id) async {
    final ref = _conversations().doc(id);
    await _deleteDocs(await ref.collection('messages').get());
    await ref.delete();
  }

  Future<void> deleteAllConversations() async {
    for (final conv in (await _conversations().get()).docs) {
      await deleteConversation(conv.id);
    }
  }

  Future<List<ChatMessage>> getMessages(String conversationId) async {
    final snap = await _conversations().doc(conversationId).collection('messages').orderBy('createdAt').get();
    return snap.docs.map(ChatMessage.fromDoc).toList();
  }

  Future<void> _deleteDocs(QuerySnapshot<Map<String, dynamic>> snap) async {
    // Firestore admite hasta 500 operaciones por lote
    for (var i = 0; i < snap.docs.length; i += 450) {
      final batch = _db.batch();
      for (final d in snap.docs.skip(i).take(450)) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }
  }

  CollectionReference<Map<String, dynamic>> _messages(String conversationId) =>
      _conversations().doc(conversationId).collection('messages');

  /// Mensaje del usuario con su id de Firestore ya reservado (para reaccionar/regenerar después).
  ChatMessage newQuestion(String conversationId, String text, {Uint8List? image}) =>
      ChatMessage(id: _messages(conversationId).doc().id, role: 'user', content: text, image: image);

  /// Solo se reenvían a Gemini las fotos de los últimos mensajes, para no gastar cuota en cada turno.
  static const _recentImages = 6;

  Content _toContent(ChatMessage m, {required bool withImage}) {
    if (!m.isUser) return Content.model([TextPart(m.content)]);
    if (m.image == null) return Content.text(m.content);
    if (!withImage) return Content.text('[El usuario envió una foto] ${m.content}');
    return Content.multi([InlineDataPart('image/jpeg', m.image!), TextPart(m.content)]);
  }

  /// Envía un mensaje (con foto opcional) a Gemini y emite la respuesta a medida que se genera.
  /// Al terminar guarda la pregunta y la respuesta en Firestore.
  /// Con [regenerate] la pregunta ya estaba guardada: solo se guarda la nueva respuesta.
  /// Cancelar la suscripción detiene la respuesta (usa [saveExchange] para guardar lo parcial).
  Stream<ChatStreamEvent> streamMessage(
    String conversationId,
    List<ChatMessage> history,
    ChatMessage question, {
    bool regenerate = false,
  }) async* {
    final prompt = [
      for (final (i, m) in history.indexed) _toContent(m, withImage: history.length - i <= _recentImages),
      _toContent(question, withImage: true),
    ];

    final buffer = StringBuffer();
    try {
      await for (final chunk in _model.generateContentStream(prompt)) {
        final text = chunk.text;
        if (text != null && text.isNotEmpty) {
          buffer.write(text);
          yield StreamDelta(text);
        }
      }
    } on QuotaExceeded {
      throw ApiException('Se alcanzó el límite gratuito de Gemini. Espera un momento e intenta de nuevo.');
    } on ServiceApiNotEnabled {
      throw ApiException('Firebase AI Logic no está activado en el proyecto de Firebase.');
    } on FirebaseAIException catch (e) {
      debugPrint('Error de Gemini: ${e.message}');
      throw ApiException('La IA no respondió: ${e.message}');
    }

    final reply = buffer.toString().trim();
    yield StreamDone(
      await saveExchange(
        conversationId,
        isFirst: history.isEmpty,
        question: question,
        answer: reply.isEmpty ? '(sin respuesta)' : reply,
        saveQuestion: !regenerate,
      ),
    );
  }

  /// Guarda pregunta + respuesta y actualiza la conversación (título si es la primera). Devuelve la respuesta.
  Future<ChatMessage> saveExchange(
    String conversationId, {
    required bool isFirst,
    required ChatMessage question,
    required String answer,
    bool saveQuestion = true,
  }) async {
    final conv = _conversations().doc(conversationId);
    final messages = conv.collection('messages');
    final answerMsg = ChatMessage(id: messages.doc().id, role: 'assistant', content: answer);
    final now = Timestamp.fromDate(answerMsg.createdAt);

    final batch = _db.batch();
    if (saveQuestion) batch.set(messages.doc(question.id), question.toMap());
    batch
      ..set(messages.doc(answerMsg.id), answerMsg.toMap())
      ..set(conv, {
        if (isFirst) 'title': _makeTitle(question.content),
        if (isFirst) 'createdAt': now,
        'updatedAt': now,
      }, SetOptions(merge: true));
    await batch.commit();
    return answerMsg;
  }

  Future<void> setLiked(String conversationId, String messageId, bool liked) =>
      _messages(conversationId).doc(messageId).update({'liked': liked});

  Future<void> deleteMessage(String conversationId, String messageId) =>
      _messages(conversationId).doc(messageId).delete();

  String _makeTitle(String text) {
    final t = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isEmpty) return 'Nueva conversación';
    return t.length > 40 ? '${t.substring(0, 40)}…' : t;
  }

  // ---------- Comentarios de testers ----------

  CollectionReference<Map<String, dynamic>> get _feedback => _db.collection('feedback');

  /// Comentarios en tiempo real (los más recientes primero): un 👍 o una respuesta nueva aparece al instante.
  Stream<List<TesterFeedback>> feedbackStream() => _feedback
      .orderBy('createdAt', descending: true)
      .limit(200)
      .snapshots()
      .map((s) => s.docs.where((d) => d.data()['createdAt'] != null).map(TesterFeedback.fromDoc).toList());

  Future<void> sendFeedback({required int rating, required String type, required String text, Uint8List? image}) =>
      _feedback.add({
        'uid': _user!.id,
        'name': _user!.name,
        'rating': rating,
        'type': type,
        'text': text.trim(),
        if (image != null) 'image': Blob(image),
        'createdAt': FieldValue.serverTimestamp(),
        'likedBy': <String>[],
        'resolved': false,
      });

  Future<void> setFeedbackLiked(String id, bool liked) => _feedback.doc(id).update({
    'likedBy': liked ? FieldValue.arrayUnion([_user!.id]) : FieldValue.arrayRemove([_user!.id]),
  });

  /// Solo admin: responde (texto vacío quita la respuesta) y marca resuelto o pendiente.
  Future<void> replyFeedback(String id, {required String reply, required bool resolved}) => _feedback.doc(id).update({
    'reply': reply.trim().isEmpty ? FieldValue.delete() : reply.trim(),
    'repliedAt': FieldValue.serverTimestamp(),
    'resolved': resolved,
  });

  Future<void> deleteFeedback(String id) => _feedback.doc(id).delete();

  // ---------- Usuarios (solo admin) ----------

  Future<List<User>> getUsers() async {
    final snap = await _users.orderBy('createdAt').get();
    return snap.docs.map(User.fromDoc).toList();
  }

  /// Crea una cuenta con usuario y contraseña sin cerrar la sesión del admin
  /// (se usa una segunda instancia de Firebase solo para el alta).
  Future<void> createUser({
    required String name,
    required String username,
    required String password,
    required String role,
  }) async {
    final clean = username.trim().toLowerCase();
    final secondary = await Firebase.initializeApp(name: 'alta-usuarios', options: Firebase.app().options);
    try {
      final cred = await _guardAuth(
        () =>
            FirebaseAuth.instanceFor(app: secondary)
                .createUserWithEmailAndPassword(email: _emailFor(clean), password: password),
      );
      await _users
          .doc(cred.user!.uid)
          .set(_newProfile(name: name.trim(), username: clean, provider: 'password', role: role));
    } finally {
      await secondary.delete();
    }
  }

  Future<void> updateUser(String id, {required String name, required String role}) async {
    await _users.doc(id).update({'name': name.trim(), 'role': role});
    if (id == _user?.id) await _loadProfile();
  }

  /// Bloquear impide entrar y acceder a sus conversaciones (las reglas de Firestore lo aplican).
  Future<void> setUserDisabled(String id, bool disabled) => _users.doc(id).update({'disabled': disabled});
}

/// Eventos de una respuesta en streaming.
sealed class ChatStreamEvent {
  const ChatStreamEvent();
}

/// Un fragmento nuevo de texto.
class StreamDelta extends ChatStreamEvent {
  final String text;
  const StreamDelta(this.text);
}

/// Respuesta completa, ya guardada en Firestore.
class StreamDone extends ChatStreamEvent {
  final ChatMessage message;
  const StreamDone(this.message);
}
