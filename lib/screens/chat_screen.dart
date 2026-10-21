import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:image_picker/image_picker.dart';

import '../api_service.dart';
import '../models.dart';
import '../theme.dart';
import 'users_screen.dart';

/// Sugerencias que se muestran en un chat vacío (las "interacciones" de Lumi); al tocarlas se envían.
const _suggestions = [
  (LumiImages.ideas, 'Dame ideas', 'Dame 3 ideas creativas para un proyecto'),
  (LumiImages.dudas, 'Resuelve mi duda', 'Explícame cómo funciona la inteligencia artificial'),
  (LumiImages.aprende, 'Aprendamos', 'Enséñame algo interesante en 2 minutos'),
  (LumiImages.cuidarte, 'Cuídame', 'Recuérdame tomar un descanso y dame un ejercicio de respiración'),
];

String _formatTime(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Agrupa por fecha relativa para el historial del menú lateral.
String _dateGroup(DateTime? d) {
  if (d == null) return 'Anteriores';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final days = today.difference(DateTime(d.year, d.month, d.day)).inDays;
  if (days <= 0) return 'Hoy';
  if (days == 1) return 'Ayer';
  if (days < 7) return 'Últimos 7 días';
  return 'Anteriores';
}

/// Pantalla principal: chat con la IA + historial de conversaciones en el menú lateral.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _api = ApiService.instance;
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  final _scroll = ScrollController();

  List<Conversation> _conversations = [];
  Conversation? _current;
  List<ChatMessage> _messages = [];
  bool _sending = false;
  bool _loadingMessages = false;
  bool _showScrollDown = false;

  // Respuesta en curso (streaming)
  StreamSubscription<ChatStreamEvent>? _subscription;
  Completer<void>? _streamDone;

  // Efecto "escribiendo": Gemini manda trozos grandes; se guardan en [_received]
  // y un temporizador los va mostrando palabra por palabra en [_streamText].
  String _streamText = '';
  String _received = '';
  ChatMessage? _finalAnswer; // respuesta ya guardada, se añade al terminar de escribirse
  Timer? _typer;
  Completer<void>? _typingDone;
  ({String conversationId, bool isFirst, ChatMessage question, ChatMessage? replacing})? _pending;

  /// Foto elegida que se enviará con el próximo mensaje.
  Uint8List? _attachment;

  /// Lumi reaccionando en grande unos segundos (p. ej. al dar ❤️).
  String? _reaction;
  Timer? _reactionTimer;

  // Mensajes que ya hicieron su animación de entrada (para no repetirla al hacer scroll)
  final _animated = <ChatMessage>{};

  @override
  void initState() {
    super.initState();
    _loadConversations();
    _input.addListener(() => setState(() {}));
    _inputFocus.addListener(() => setState(() {}));
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _typer?.cancel();
    _reactionTimer?.cancel();
    _input.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final show = _scroll.position.maxScrollExtent - _scroll.offset > 200;
    if (show != _showScrollDown) setState(() => _showScrollDown = show);
  }

  void _showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
  }

  Future<void> _loadConversations() async {
    try {
      final list = await _api.getConversations();
      if (!mounted) return;
      setState(() {
        _conversations = list;
        // Refresca el título de la conversación abierta (se pone tras el primer mensaje)
        final id = _current?.id;
        if (id != null) _current = list.where((c) => c.id == id).firstOrNull ?? _current;
      });
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _openConversation(Conversation c) async {
    setState(() {
      _current = c;
      _messages = [];
      _loadingMessages = true;
    });
    try {
      final msgs = await _api.getMessages(c.id);
      if (mounted && _current?.id == c.id) {
        setState(() {
          _messages = msgs;
          _animated.addAll(msgs); // el historial aparece sin animación
        });
      }
      _scrollToBottom(animate: false);
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _loadingMessages = false);
    }
  }

  void _newChat() {
    setState(() {
      _current = null;
      _messages = [];
    });
  }

  /// Envía lo escrito (y la foto adjunta, si hay). [preset] envía un texto ya hecho (sugerencias).
  Future<void> _send([String? preset]) async {
    var text = (preset ?? _input.text).trim();
    final image = preset == null ? _attachment : null;
    if ((text.isEmpty && image == null) || _sending) return;
    if (text.isEmpty) text = '¿Qué ves en esta foto?';
    HapticFeedback.lightImpact();
    _input.clear();
    final conv = _current ??= _api.newConversation();
    final history = List.of(_messages);
    final question = _api.newQuestion(conv.id, text, image: image);
    setState(() {
      _attachment = null;
      _messages.add(question);
    });
    await _runStream(conv.id, history: history, question: question);
  }

  /// Pide otra respuesta para la última pregunta. La anterior se borra solo si la nueva llega bien.
  Future<void> _regenerate(ChatMessage answer) async {
    final i = _messages.indexOf(answer);
    if (_sending || i < 1 || _current == null) return;
    HapticFeedback.selectionClick();
    setState(() => _messages.removeAt(i));
    await _runStream(_current!.id, history: _messages.sublist(0, i - 1), question: _messages[i - 1], replacing: answer);
  }

  Future<void> _runStream(
    String conversationId, {
    required List<ChatMessage> history,
    required ChatMessage question,
    ChatMessage? replacing,
  }) async {
    _pending = (conversationId: conversationId, isFirst: history.isEmpty, question: question, replacing: replacing);
    setState(() {
      _sending = true;
      _streamText = '';
      _received = '';
      _finalAnswer = null;
    });
    _scrollToBottom();

    final done = _streamDone = Completer<void>();
    final typing = _typingDone = Completer<void>();
    _typer = Timer.periodic(_typeInterval, (_) => _typeNextWords());
    try {
      _subscription = _api
          .streamMessage(conversationId, history, question, regenerate: replacing != null)
          .listen(
            _onStreamEvent,
            onError: (Object e) => done.isCompleted ? null : done.completeError(e),
            onDone: () => done.isCompleted ? null : done.complete(),
            cancelOnError: true,
          );
      await done.future;
      // Gemini ya terminó: se espera a que acabe de "escribirse" en pantalla
      await typing.future;
      _loadConversations();
    } catch (e) {
      _finishTyping();
      if (mounted) {
        setState(() {
          if (replacing != null) {
            // Regenerar falló: vuelve la respuesta anterior
            _messages.add(replacing);
          } else {
            // No se guardó nada: quitamos el mensaje y lo devolvemos al campo para reintentar
            _messages.remove(question);
            _input.text = question.content;
            _attachment = question.image;
          }
        });
      }
      _showReaction(LumiImages.triste);
      _showError(e);
    } finally {
      _subscription = null;
      if (mounted) {
        setState(() {
          _sending = false;
          _streamText = '';
        });
      }
    }
  }

  void _onStreamEvent(ChatStreamEvent event) {
    switch (event) {
      case StreamDelta(:final text):
        _received += text;
      case StreamDone(:final message):
        _finalAnswer = message;
        // Regenerar: la nueva respuesta ya está guardada, se borra la anterior
        final old = _pending?.replacing?.id;
        if (old != null) _api.deleteMessage(_pending!.conversationId, old);
    }
  }

  static const _typeInterval = Duration(milliseconds: 40); // ~25 palabras por segundo

  /// Muestra las siguientes palabras de la respuesta. Si se acumula mucho texto pendiente
  /// acelera un poco para no quedarse atrás de Gemini.
  void _typeNextWords() {
    if (!mounted) return;
    final pending = _received.length - _streamText.length;
    if (pending > 0) {
      final words = 1 + pending ~/ 240;
      setState(() => _streamText = _received.substring(0, _wordsEnd(_received, _streamText.length, words)));
      // Sigue el texto mientras se escribe, salvo que el usuario haya subido a leer
      if (!_showScrollDown) _scrollToBottom(animate: false);
    } else if (_finalAnswer != null) {
      // Ya se escribió todo: la burbuja se sustituye por el mensaje guardado (sin volver a animarse)
      final message = _finalAnswer!;
      _animated.add(message);
      setState(() {
        _messages.add(message);
        _streamText = '';
        _received = '';
        _finalAnswer = null;
      });
      _finishTyping();
    }
  }

  /// Posición donde terminan las siguientes [words] palabras a partir de [from] (incluye el espacio previo).
  static int _wordsEnd(String s, int from, int words) {
    bool isSpace(int c) => c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09;
    var i = from;
    for (var w = 0; w < words && i < s.length; w++) {
      while (i < s.length && isSpace(s.codeUnitAt(i))) {
        i++;
      }
      while (i < s.length && !isSpace(s.codeUnitAt(i))) {
        i++;
      }
    }
    return i;
  }

  void _finishTyping() {
    _typer?.cancel();
    _typer = null;
    final typing = _typingDone;
    if (typing != null && !typing.isCompleted) typing.complete();
  }

  /// Detiene la respuesta y guarda lo que ya se veía escrito en pantalla.
  void _stop() {
    final sub = _subscription;
    final pending = _pending;
    if (sub == null || pending == null) return;
    sub.cancel();
    // Si Gemini ya había terminado (respuesta guardada) solo se muestra completa de una vez
    final finished = _finalAnswer;
    if (finished != null) {
      _animated.add(finished);
      setState(() => _messages.add(finished));
      _streamText = _received = '';
      _finalAnswer = null;
      _finishTyping();
      if (!_streamDone!.isCompleted) _streamDone!.complete();
      return;
    }
    _finishTyping();
    final partial = _streamText.trim();
    final replacing = pending.replacing;
    if (partial.isNotEmpty) {
      final m = ChatMessage(role: 'assistant', content: partial);
      _animated.add(m);
      setState(() => _messages.add(m));
      _api
          .saveExchange(
            pending.conversationId,
            isFirst: pending.isFirst,
            question: pending.question,
            answer: partial,
            saveQuestion: replacing == null,
          )
          .then((saved) {
            if (replacing?.id != null) _api.deleteMessage(pending.conversationId, replacing!.id!);
            // Reemplaza el mensaje local por el guardado (con id, para poder reaccionar)
            final i = _messages.indexOf(m);
            if (mounted && i >= 0) setState(() => _messages[i] = saved);
            _animated.add(saved);
            _loadConversations();
          }, onError: _showError);
    } else if (replacing != null) {
      // Se detuvo antes de escribir: se queda la respuesta anterior
      setState(() => _messages.add(replacing));
    } else {
      // Sin texto todavía: no se guarda nada y el mensaje vuelve al campo
      setState(() => _messages.remove(pending.question));
      _input.text = pending.question.content;
      _attachment = pending.question.image;
    }
    _streamText = _received = '';
    if (!_streamDone!.isCompleted) _streamDone!.complete();
  }

  Future<void> _toggleLike(ChatMessage m) async {
    final id = m.id;
    final convId = _current?.id;
    if (id == null || convId == null) return;
    HapticFeedback.mediumImpact();
    setState(() => m.liked = !m.liked);
    if (m.liked) _showReaction(LumiImages.amor);
    try {
      await _api.setLiked(convId, id, m.liked);
    } catch (e) {
      if (mounted) setState(() => m.liked = !m.liked);
      _showError(e);
    }
  }

  /// Muestra a Lumi en grande durante un momento (feliz con corazón, triste si algo falla…).
  void _showReaction(String sticker) {
    if (!mounted) return;
    _reactionTimer?.cancel();
    setState(() => _reaction = sticker);
    _reactionTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _reaction = null);
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      // Se reduce y comprime en el propio teléfono: así cabe en Firestore y gasta menos cuota de Gemini
      final file = await ImagePicker().pickImage(source: source, maxWidth: 1024, maxHeight: 1024, imageQuality: 70);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 750000) {
        _showError('La foto es demasiado pesada. Prueba con otra.');
        return;
      }
      setState(() => _attachment = bytes);
      _inputFocus.requestFocus();
    } catch (e) {
      _showError('No se pudo abrir ${source == ImageSource.camera ? 'la cámara' : 'la galería'}');
    }
  }

  void _showAttachMenu() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const _Sticker(LumiImages.curioso, height: 64),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('¡Muéstrame una foto y te digo qué veo!', style: Theme.of(ctx).textTheme.titleMedium),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _AttachOption(
                      icon: Icons.photo_camera_rounded,
                      label: 'Cámara',
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickImage(ImageSource.camera);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _AttachOption(
                      icon: Icons.photo_library_rounded,
                      label: 'Galería',
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickImage(ImageSource.gallery);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final end = _scroll.position.maxScrollExtent;
      if (animate) {
        _scroll.animateTo(end, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
      } else {
        _scroll.jumpTo(end);
      }
    });
  }

  Future<bool> _confirm(String title, String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Borrar')),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _deleteConversation(Conversation c) async {
    if (!await _confirm('Borrar conversación', '¿Borrar "${c.title}"? Esta acción no se puede deshacer.')) return;
    try {
      await _api.deleteConversation(c.id);
      if (_current?.id == c.id) _newChat();
      await _loadConversations();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _deleteAll() async {
    if (!await _confirm('Borrar todo', '¿Borrar todas tus conversaciones?')) return;
    try {
      await _api.deleteAllConversations();
      _newChat();
      await _loadConversations();
    } catch (e) {
      _showError(e);
    }
  }

  /// Poca altura disponible (teléfono en horizontal y/o teclado abierto): todo se hace más compacto.
  bool get _compact => MediaQuery.sizeOf(context).height - MediaQuery.viewInsetsOf(context).bottom < 420;

  @override
  Widget build(BuildContext context) {
    final compact = _compact;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        toolbarHeight: compact ? 44 : null,
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          // Chat nuevo: logo de Lumi; conversación abierta: su título
          child: _current == null
              ? Image.asset(LumiImages.logo, height: compact ? 28 : 38, key: const ValueKey('logo'))
              : Text(
                  _current!.title,
                  key: ValueKey(_current!.title),
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
        ),
        actions: [
          IconButton(tooltip: 'Nuevo chat', icon: const Icon(Icons.edit_square), onPressed: _newChat),
          if (_current != null)
            IconButton(
              tooltip: 'Borrar conversación',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _deleteConversation(_current!),
            ),
        ],
      ),
      drawer: _buildDrawer(),
      // En horizontal respeta los bordes con cámara/notch a los lados
      body: SafeArea(
        top: false,
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            children: [
              Expanded(child: _buildChatArea(compact)),
              // La caja de texto nunca supera el alto disponible: si no cabe, se desplaza en vez de desbordarse
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: constraints.maxHeight),
                child: SingleChildScrollView(child: _buildInput(compact)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatArea(bool compact) {
    return Stack(
      children: [
        Positioned.fill(child: _buildMessages()),
        // Lumi reaccionando en grande (❤️, error…)
        Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                transitionBuilder: (child, a) => ScaleTransition(
                  scale: CurvedAnimation(parent: a, curve: Curves.elasticOut, reverseCurve: Curves.easeIn),
                  child: FadeTransition(opacity: a, child: child),
                ),
                child: _reaction == null
                    ? const SizedBox.shrink()
                    : _Sticker(_reaction!, key: ValueKey(_reaction), height: compact ? 90 : 170),
              ),
            ),
          ),
        ),
        Positioned(
          right: 16,
          bottom: 8,
          child: AnimatedScale(
            scale: _showScrollDown ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: FloatingActionButton.small(
              heroTag: null,
              tooltip: 'Ir al final',
              onPressed: _scrollToBottom,
              child: const Icon(Icons.keyboard_arrow_down_rounded),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDrawer() {
    final user = _api.currentUser!;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    // Con poca altura (horizontal) todo el menú se vuelve una sola lista desplazable
    final compact = MediaQuery.sizeOf(context).height < 560;

    final header = <Widget>[
      Padding(
        padding: EdgeInsets.fromLTRB(16, compact ? 8 : 16, 16, 0),
        child: Image.asset(LumiImages.logo, height: compact ? 40 : 64),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(16, compact ? 6 : 12, 16, compact ? 4 : 8),
        child: Row(
          children: [
            _Avatar(letter: user.name.isNotEmpty ? user.name[0].toUpperCase() : '?', size: compact ? 36 : 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.name, style: text.titleMedium, overflow: TextOverflow.ellipsis),
                  Text(
                    '@${user.username}${user.isAdmin ? ' · admin' : ''}',
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(12, compact ? 4 : 8, 12, compact ? 4 : 8),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(padding: EdgeInsets.symmetric(vertical: compact ? 10 : 14)),
            onPressed: () {
              Navigator.pop(context);
              _newChat();
            },
            icon: const Icon(Icons.add),
            label: const Text('Nuevo chat'),
          ),
        ),
      ),
    ];

    final empty = Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Sticker(LumiImages.dormido, height: compact ? 60 : 90),
          const SizedBox(height: 8),
          Text('Aún no hay conversaciones', style: TextStyle(color: scheme.onSurfaceVariant)),
        ],
      ),
    );

    // Conversaciones con encabezados de fecha intercalados
    final conversations = <Widget>[];
    String? lastGroup;
    for (final c in _conversations) {
      final g = _dateGroup(c.updatedAt);
      if (g != lastGroup) {
        lastGroup = g;
        conversations.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text(
              g,
              style: text.labelMedium?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600),
            ),
          ),
        );
      }
      conversations.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: ListTile(
            dense: true,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            selected: c.id == _current?.id,
            selectedTileColor: scheme.secondaryContainer,
            selectedColor: scheme.onSecondaryContainer,
            leading: const Icon(Icons.chat_bubble_outline, size: 20),
            title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              tooltip: 'Borrar',
              onPressed: () => _deleteConversation(c),
            ),
            onTap: () {
              Navigator.pop(context);
              _openConversation(c);
            },
          ),
        ),
      );
    }

    final footer = <Widget>[
      const Divider(height: 1),
      if (_conversations.isNotEmpty)
        ListTile(
          dense: compact,
          leading: const Icon(Icons.delete_sweep_outlined),
          title: const Text('Borrar todas las conversaciones'),
          onTap: () {
            Navigator.pop(context);
            _deleteAll();
          },
        ),
      if (user.isAdmin)
        ListTile(
          dense: compact,
          leading: const Icon(Icons.admin_panel_settings_outlined),
          title: const Text('Administrar usuarios'),
          onTap: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (_) => const UsersScreen()));
          },
        ),
      ListTile(
        dense: compact,
        leading: const Icon(Icons.logout),
        title: const Text('Cerrar sesión'),
        onTap: () {
          Navigator.pop(context);
          _api.logout();
        },
      ),
    ];

    return Drawer(
      child: SafeArea(
        child: compact
            ? ListView(children: [...header, if (conversations.isEmpty) empty else ...conversations, ...footer])
            : Column(
                children: [
                  ...header,
                  Expanded(
                    child: conversations.isEmpty ? Center(child: empty) : ListView(children: conversations),
                  ),
                  ...footer,
                ],
              ),
      ),
    );
  }

  Widget _buildMessages() {
    if (_loadingMessages) return const Center(child: CircularProgressIndicator());
    if (_messages.isEmpty) {
      return _EmptyState(name: _api.currentUser!.name, onSuggestion: _send);
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      // Al final: la respuesta en curso, o las respuestas rápidas tras la última respuesta de Lumi
      itemCount: _messages.length + 1,
      itemBuilder: (_, i) {
        if (i == _messages.length) {
          if (_sending) {
            if (_streamText.isEmpty) {
              return _TypingBubble(lookingAtPhoto: _pending?.question.image != null);
            }
            return _MessageBubble(
              message: ChatMessage(role: 'assistant', content: _streamText),
              streaming: true,
            );
          }
          if (_messages.last.isUser) return const SizedBox.shrink();
          return _QuickReplies(onTap: _send);
        }
        final m = _messages[i];
        final animate = _animated.add(m);
        final isLastAnswer = !m.isUser && i == _messages.length - 1;
        return _EnterAnimation(
          key: ObjectKey(m),
          enabled: animate,
          fromRight: m.isUser,
          child: _MessageBubble(
            message: m,
            onLike: m.isUser || m.id == null ? null : () => _toggleLike(m),
            onRegenerate: isLastAnswer && !_sending ? () => _regenerate(m) : null,
          ),
        );
      },
    );
  }

  Widget _buildInput(bool compact) {
    final scheme = Theme.of(context).colorScheme;
    final canSend = (_input.text.trim().isNotEmpty || _attachment != null) && !_sending;
    final thumb = compact ? 56.0 : 96.0;
    return SafeArea(
      top: false,
      child: Padding(
        padding: compact ? const EdgeInsets.fromLTRB(8, 2, 8, 4) : const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.fromLTRB(4, 4, 6, 4),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: _inputFocus.hasFocus ? scheme.primary : scheme.outlineVariant,
              width: _inputFocus.hasFocus ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Vista previa de la foto que se va a enviar
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                child: _attachment == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Image.memory(_attachment!, height: thumb, width: thumb, fit: BoxFit.cover),
                              ),
                              Positioned(
                                top: -8,
                                right: -8,
                                child: IconButton.filled(
                                  tooltip: 'Quitar foto',
                                  visualDensity: VisualDensity.compact,
                                  iconSize: 16,
                                  onPressed: () => setState(() => _attachment = null),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Enviar una foto',
                    onPressed: _sending ? null : _showAttachMenu,
                    color: scheme.primary,
                    icon: const Icon(Icons.add_photo_alternate_rounded),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      focusNode: _inputFocus,
                      minLines: 1,
                      maxLines: compact ? 2 : 6,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: _attachment != null ? 'Pregúntale algo sobre la foto…' : 'Escríbele a Lumi…',
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                      ),
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(bottom: 2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: canSend || _sending ? scheme.primary : scheme.surfaceContainerHighest,
                    ),
                    child: _sending
                        ? IconButton(
                            tooltip: 'Detener',
                            onPressed: _stop,
                            icon: Icon(Icons.stop_rounded, color: scheme.onPrimary),
                          )
                        : IconButton(
                            tooltip: 'Enviar',
                            onPressed: canSend ? _send : null,
                            icon: Icon(
                              Icons.arrow_upward_rounded,
                              color: canSend ? scheme.onPrimary : scheme.onSurfaceVariant.withValues(alpha: 0.5),
                            ),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Botón grande de "Cámara" / "Galería" en el menú de adjuntar.
class _AttachOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _AttachOption({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            children: [
              Icon(icon, size: 34, color: scheme.primary),
              const SizedBox(height: 6),
              Text(label, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}

/// Respuestas rápidas para seguir la conversación con un toque.
class _QuickReplies extends StatelessWidget {
  final void Function(String) onTap;
  const _QuickReplies({required this.onTap});

  static const _options = [
    ('🧸', 'Más simple', 'Explícamelo más simple, por favor'),
    ('💡', 'Dame un ejemplo', 'Dame un ejemplo'),
    ('📝', 'Resúmelo', 'Resúmelo en pocas palabras'),
    ('➡️', 'Continúa', 'Continúa'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 42, top: 2),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (emoji, label, prompt) in _options)
            ActionChip(
              avatar: Text(emoji),
              label: Text(label),
              shape: const StadiumBorder(),
              side: BorderSide(color: scheme.outlineVariant),
              backgroundColor: scheme.surfaceContainerLow,
              onPressed: () => onTap(prompt),
            ),
        ],
      ),
    );
  }
}

/// Foto a pantalla completa, con zoom.
class _PhotoViewer extends StatelessWidget {
  final Uint8List image;
  final Object heroTag;
  const _PhotoViewer({required this.image, required this.heroTag});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: Center(
        child: InteractiveViewer(
          maxScale: 5,
          child: Hero(tag: heroTag, child: Image.memory(image)),
        ),
      ),
    );
  }
}

/// Pantalla de bienvenida con sugerencias tocables.
class _EmptyState extends StatelessWidget {
  final String name;
  final void Function(String) onSuggestion;
  const _EmptyState({required this.name, required this.onSuggestion});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.6, end: 1),
                duration: const Duration(milliseconds: 700),
                curve: Curves.elasticOut,
                builder: (_, s, child) => Transform.scale(scale: s, child: child),
                child: const _Sticker(LumiImages.saluda, height: 150),
              ),
              const SizedBox(height: 12),
              Text('¡Hola, $name!', style: text.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text(
                '¡Soy Lumi, tu asistente! ¿En qué te ayudo hoy?',
                textAlign: TextAlign.center,
                style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 28),
              LayoutBuilder(
                builder: (context, c) {
                  final cols = c.maxWidth > 360 ? 2 : 1;
                  final w = (c.maxWidth - 12 * (cols - 1)) / cols;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final (image, title, detail) in _suggestions)
                        SizedBox(
                          width: w,
                          child: _SuggestionCard(
                            image: image,
                            title: title,
                            detail: detail,
                            onTap: () => onSuggestion(detail),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta con una ilustración de Lumi y una frase lista para enviar.
class _SuggestionCard extends StatelessWidget {
  final String image;
  final String title;
  final String detail;
  final VoidCallback onTap;
  const _SuggestionCard({required this.image, required this.title, required this.detail, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: scheme.outlineVariant, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(aspectRatio: 1.35, child: Image.asset(image, fit: BoxFit.cover)),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: scheme.primary)),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ilustración de Lumi. Las imágenes tienen fondo lavanda, así que en modo oscuro
/// se muestran dentro de un círculo claro para que no se vea el recuadro.
class _Sticker extends StatelessWidget {
  final String image;
  final double height;
  const _Sticker(this.image, {super.key, required this.height});

  @override
  Widget build(BuildContext context) {
    final img = Image.asset(image, height: height, fit: BoxFit.contain);
    if (Theme.of(context).brightness == Brightness.light) return img;
    return Container(
      padding: EdgeInsets.all(height * 0.08),
      decoration: const BoxDecoration(color: LumiColors.lavender, shape: BoxShape.circle),
      child: ClipOval(child: img),
    );
  }
}

/// Fade + deslizamiento para mensajes nuevos.
class _EnterAnimation extends StatelessWidget {
  final bool enabled;
  final bool fromRight;
  final Widget child;
  const _EnterAnimation({super.key, required this.enabled, required this.fromRight, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset((fromRight ? 24 : -24) * (1 - t), 8 * (1 - t)), child: child),
      ),
      child: child,
    );
  }
}

class _Avatar extends StatelessWidget {
  final String letter;
  final double size;
  const _Avatar({required this.letter, this.size = 32});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      child: Text(
        letter,
        style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _BotAvatar extends StatelessWidget {
  static const size = 34.0;
  const _BotAvatar();

  @override
  Widget build(BuildContext context) {
    // Lumi (del ícono de la app) con un aro morado
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(1.5),
      decoration: const BoxDecoration(shape: BoxShape.circle, color: LumiColors.purple),
      child: ClipOval(child: Image.asset(LumiImages.icon, fit: BoxFit.cover)),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool streaming;
  final VoidCallback? onLike;
  final VoidCallback? onRegenerate;
  const _MessageBubble({required this.message, this.streaming = false, this.onLike, this.onRegenerate});

  void _openPhoto(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _PhotoViewer(image: message.image!, heroTag: message),
      ),
    );
  }

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: message.content));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Mensaje copiado'), duration: Duration(seconds: 1)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // En horizontal/tablet las burbujas no pasan de 600 px para que se lean cómodas
    final maxWidth = (MediaQuery.sizeOf(context).width * (message.isUser ? 0.78 : 0.85)).clamp(0.0, 600.0);
    final meta = TextStyle(fontSize: 11, color: scheme.onSurfaceVariant);

    if (message.isUser) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (message.image != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: GestureDetector(
                  onTap: () => _openPhoto(context),
                  child: Hero(
                    tag: message,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxWidth * 0.8, maxHeight: 260),
                        child: Image.memory(message.image!, fit: BoxFit.cover, gaplessPlayback: true),
                      ),
                    ),
                  ),
                ),
              ),
            GestureDetector(
              onLongPress: () => _copy(context),
              child: Container(
                constraints: BoxConstraints(maxWidth: maxWidth),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [scheme.primary, Color.lerp(scheme.primary, Colors.white, 0.25)!],
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(6),
                  ),
                ),
                child: SelectableText(message.content, style: TextStyle(color: scheme.onPrimary, height: 1.4)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 4),
              child: Text(_formatTime(message.createdAt), style: meta),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _BotAvatar(),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(6),
                      topRight: Radius.circular(20),
                      bottomLeft: Radius.circular(20),
                      bottomRight: Radius.circular(20),
                    ),
                  ),
                  child: SelectionArea(
                    child: GptMarkdown(
                      // Cursor al final mientras la IA sigue escribiendo
                      streaming ? '${message.content} ▍' : message.content,
                      style: TextStyle(color: scheme.onSurface, height: 1.45, fontSize: 15),
                    ),
                  ),
                ),
                if (!streaming)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text(_formatTime(message.createdAt), style: meta),
                      ),
                      IconButton(
                        tooltip: 'Copiar',
                        visualDensity: VisualDensity.compact,
                        iconSize: 16,
                        color: scheme.onSurfaceVariant,
                        onPressed: () => _copy(context),
                        icon: const Icon(Icons.copy_rounded),
                      ),
                      if (onLike != null)
                        IconButton(
                          tooltip: message.liked ? 'Quitar me gusta' : 'Me gusta',
                          visualDensity: VisualDensity.compact,
                          iconSize: 18,
                          onPressed: onLike,
                          icon: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            transitionBuilder: (child, a) => ScaleTransition(
                              scale: CurvedAnimation(parent: a, curve: Curves.elasticOut),
                              child: child,
                            ),
                            child: Icon(
                              message.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                              key: ValueKey(message.liked),
                              color: message.liked ? LumiColors.heart : scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      if (onRegenerate != null)
                        IconButton(
                          tooltip: 'Otra respuesta',
                          visualDensity: VisualDensity.compact,
                          iconSize: 18,
                          color: scheme.onSurfaceVariant,
                          onPressed: onRegenerate,
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Indicador "escribiendo…" con tres puntos animados.
class _TypingBubble extends StatefulWidget {
  /// Si el mensaje lleva foto, Lumi aparece curioso "mirando la foto".
  final bool lookingAtPhoto;
  const _TypingBubble({this.lookingAtPhoto = false});

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Lumi pensando (o curioso mirando la foto) mientras llega la respuesta
          _Sticker(widget.lookingAtPhoto ? LumiImages.curioso : LumiImages.pensando, height: 72),
          const SizedBox(width: 4),
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
            ),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (_, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) {
                  // Cada punto sube y baja con un desfase
                  final t = ((_controller.value - i * 0.15) % 1.0);
                  final lift = t < 0.4 ? Curves.easeInOut.transform(1 - (t - 0.2).abs() / 0.2) : 0.0;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                    transform: Matrix4.translationValues(0, -5 * lift, 0),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color.lerp(scheme.outline, scheme.primary, lift),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
