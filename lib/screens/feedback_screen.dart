import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../api_service.dart';
import '../models.dart';
import '../theme.dart';

/// Tipos de comentario: clave guardada en Firestore, emoji, nombre y color.
const _types = [
  ('bug', '🐞', 'Error', Color(0xFFFF8A65)),
  ('idea', '💡', 'Idea', Color(0xFFFFC94D)),
  ('love', '💜', 'Me gusta', LumiColors.purple),
];

(String, String, String, Color) _typeOf(String key) =>
    _types.firstWhere((t) => t.$1 == key, orElse: () => _types.first);

String _timeAgo(DateTime? d) {
  if (d == null) return 'ahora';
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'hace un momento';
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'hace ${diff.inHours} h';
  if (diff.inDays == 1) return 'ayer';
  if (diff.inDays < 7) return 'hace ${diff.inDays} días';
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

/// Filtros de la lista.
enum _Filter { all, bug, idea, love, pending, resolved }

/// Comentarios de los testers: calificación, tipo, texto y captura; se ven en vivo,
/// se les da 👍 y el admin responde o marca como resuelto.
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _api = ApiService.instance;
  final _text = TextEditingController();
  late final Stream<List<TesterFeedback>> _stream = _api.feedbackStream();

  int _rating = 0;
  String _type = 'bug';
  Uint8List? _image;
  bool _sending = false;
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  bool get _canSend => _rating > 0 && _text.text.trim().isNotEmpty && !_sending;

  Future<void> _pickImage() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1080,
        maxHeight: 1920,
        imageQuality: 70,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 750000) return _snack('La captura es demasiado pesada. Prueba con otra.');
      setState(() => _image = bytes);
    } catch (_) {
      _snack('No se pudo abrir la galería');
    }
  }

  Future<void> _send() async {
    if (!_canSend) return;
    FocusScope.of(context).unfocus();
    setState(() => _sending = true);
    try {
      await _api.sendFeedback(rating: _rating, type: _type, text: _text.text, image: _image);
      HapticFeedback.mediumImpact();
      setState(() {
        _rating = 0;
        _image = null;
        _text.clear();
      });
      _snack('¡Gracias por tu comentario! 💜');
    } catch (e) {
      _snack('No se pudo enviar: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleLike(TesterFeedback f) async {
    HapticFeedback.selectionClick();
    try {
      await _api.setFeedbackLiked(f.id, !f.likedBy.contains(_api.currentUser!.id));
    } catch (e) {
      _snack('No se pudo guardar tu 👍');
    }
  }

  Future<void> _reply(TesterFeedback f) async {
    final controller = TextEditingController(text: f.reply);
    var resolved = f.resolved || f.reply == null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Responder al tester'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 2,
                maxLines: 5,
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'Escribe tu respuesta…'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Marcar como resuelto'),
                value: resolved,
                onChanged: (v) => setLocal(() => resolved = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await _api.replyFeedback(f.id, reply: controller.text, resolved: resolved);
      _snack(resolved ? 'Respuesta guardada · ✅ Resuelto' : 'Respuesta guardada');
    } catch (e) {
      _snack('No se pudo guardar la respuesta');
    }
  }

  Future<void> _delete(TesterFeedback f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar comentario'),
        content: const Text('¿Seguro que quieres borrarlo? No se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.deleteFeedback(f.id);
    } catch (e) {
      _snack('No se pudo borrar');
    }
  }

  bool _matches(TesterFeedback f) => switch (_filter) {
    _Filter.all => true,
    _Filter.bug => f.type == 'bug',
    _Filter.idea => f.type == 'idea',
    _Filter.love => f.type == 'love',
    _Filter.pending => !f.resolved,
    _Filter.resolved => f.resolved,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Comentarios de testers')),
      body: SafeArea(
        top: false,
        child: StreamBuilder<List<TesterFeedback>>(
          stream: _stream,
          builder: (context, snap) {
            final all = snap.data ?? const <TesterFeedback>[];
            final visible = all.where(_matches).toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _Summary(items: all),
                const SizedBox(height: 16),
                _buildComposer(),
                const SizedBox(height: 20),
                _buildFilters(all),
                const SizedBox(height: 12),
                if (snap.hasError)
                  const _EmptyNote(image: LumiImages.triste, text: 'No se pudieron cargar los comentarios.')
                else if (!snap.hasData)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (visible.isEmpty)
                  _EmptyNote(
                    image: all.isEmpty ? LumiImages.feliz : LumiImages.curioso,
                    text: all.isEmpty
                        ? 'Aún no hay comentarios. ¡Sé el primero en opinar!'
                        : 'Nada por aquí con este filtro.',
                  )
                else
                  for (final f in visible)
                    _FeedbackCard(
                      key: ValueKey(f.id),
                      feedback: f,
                      me: _api.currentUser!,
                      onLike: () => _toggleLike(f),
                      onReply: () => _reply(f),
                      onDelete: () => _delete(f),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildComposer() {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('¿Qué te pareció Lumi?', style: text.titleMedium),
            const SizedBox(height: 8),
            // Estrellas tocables con un pequeño rebote
            Row(
              children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    tooltip: '$i estrella${i == 1 ? '' : 's'}',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      setState(() => _rating = i);
                    },
                    icon: AnimatedScale(
                      scale: i <= _rating ? 1.15 : 1,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutBack,
                      child: Icon(
                        i <= _rating ? Icons.star_rounded : Icons.star_outline_rounded,
                        size: 34,
                        color: i <= _rating ? const Color(0xFFFFC94D) : scheme.outline,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                for (final (key, emoji, label, _) in _types)
                  ChoiceChip(
                    avatar: Text(emoji),
                    label: Text(label),
                    selected: _type == key,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _type = key),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              minLines: 2,
              maxLines: 5,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: switch (_type) {
                  'bug' => '¿Qué falló? ¿Qué estabas haciendo cuando pasó?',
                  'idea' => '¿Qué te gustaría que Lumi hiciera?',
                  _ => '¿Qué es lo que más te gustó?',
                },
              ),
            ),
            if (_image != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.memory(_image!, height: 110, fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: -8,
                      right: -8,
                      child: IconButton.filled(
                        tooltip: 'Quitar captura',
                        visualDensity: VisualDensity.compact,
                        iconSize: 16,
                        onPressed: () => setState(() => _image = null),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _sending ? null : _pickImage,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(_image == null ? 'Adjuntar captura' : 'Cambiar captura'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _canSend ? _send : null,
                  icon: _sending
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send_rounded),
                  label: const Text('Enviar'),
                ),
              ],
            ),
            if (_rating == 0)
              Text(
                'Elige de 1 a 5 estrellas para poder enviar',
                style: text.bodySmall?.copyWith(color: scheme.outline),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters(List<TesterFeedback> all) {
    int count(bool Function(TesterFeedback) test) => all.where(test).length;
    final options = [
      (_Filter.all, 'Todos', all.length),
      (_Filter.bug, '🐞 Errores', count((f) => f.type == 'bug')),
      (_Filter.idea, '💡 Ideas', count((f) => f.type == 'idea')),
      (_Filter.love, '💜 Me gusta', count((f) => f.type == 'love')),
      (_Filter.pending, '⏳ Pendientes', count((f) => !f.resolved)),
      (_Filter.resolved, '✅ Resueltos', count((f) => f.resolved)),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (filter, label, n) in options)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text('$label · $n'),
                selected: _filter == filter,
                showCheckmark: false,
                onSelected: (_) => setState(() => _filter = filter),
              ),
            ),
        ],
      ),
    );
  }
}

/// Encabezado con Lumi y el resumen en vivo (promedio de estrellas y totales).
class _Summary extends StatelessWidget {
  final List<TesterFeedback> items;
  const _Summary({required this.items});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final avg = items.isEmpty ? 0.0 : items.map((f) => f.rating).reduce((a, b) => a + b) / items.length;
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.asset(LumiImages.amor, height: 92, width: 92, fit: BoxFit.cover),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('¡Ayúdame a mejorar!', style: text.titleLarge),
              const SizedBox(height: 4),
              Text(
                items.isEmpty
                    ? 'Cuéntame qué te gusta y qué falla.'
                    : '⭐ ${avg.toStringAsFixed(1)} de promedio · ${items.length} comentario${items.length == 1 ? '' : 's'}',
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyNote extends StatelessWidget {
  final String image;
  final String text;
  const _EmptyNote({required this.image, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          ClipOval(child: Image.asset(image, height: 96, width: 96, fit: BoxFit.cover)),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  final TesterFeedback feedback;
  final User me;
  final VoidCallback onLike;
  final VoidCallback onReply;
  final VoidCallback onDelete;

  const _FeedbackCard({
    super.key,
    required this.feedback,
    required this.me,
    required this.onLike,
    required this.onReply,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final f = feedback;
    final (_, emoji, label, color) = _typeOf(f.type);
    final liked = f.likedBy.contains(me.id);
    final canDelete = f.uid == me.id || me.isAdmin;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: f.resolved ? Colors.green.withValues(alpha: 0.5) : scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: scheme.primaryContainer,
                  child: Text(f.name.isNotEmpty ? f.name[0].toUpperCase() : '?', style: const TextStyle(fontSize: 14)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.uid == me.id ? '${f.name} (tú)' : f.name,
                        style: text.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(_timeAgo(f.createdAt), style: text.bodySmall?.copyWith(color: scheme.outline)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('$emoji $label', style: text.labelMedium),
                ),
                if (canDelete)
                  PopupMenuButton<String>(
                    tooltip: 'Más opciones',
                    onSelected: (v) => v == 'reply' ? onReply() : onDelete(),
                    itemBuilder: (_) => [
                      if (me.isAdmin)
                        PopupMenuItem(value: 'reply', child: Text(f.reply == null ? 'Responder' : 'Editar respuesta')),
                      const PopupMenuItem(value: 'delete', child: Text('Borrar')),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (var i = 1; i <= 5; i++)
                  Icon(
                    i <= f.rating ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 18,
                    color: i <= f.rating ? const Color(0xFFFFC94D) : scheme.outline,
                  ),
                if (f.resolved) ...[
                  const SizedBox(width: 10),
                  Text('✅ Resuelto', style: text.labelMedium?.copyWith(color: Colors.green)),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: SelectableText(f.text, style: text.bodyMedium),
            ),
            if (f.image != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _PhotoViewer(image: f.image!, tag: f.id),
                    ),
                  ),
                  child: Hero(
                    tag: f.id,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.memory(f.image!, height: 150, fit: BoxFit.cover),
                    ),
                  ),
                ),
              ),
            // Respuesta del equipo
            if (f.reply != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 10, right: 6),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipOval(child: Image.asset(LumiImages.icon, height: 26, width: 26, fit: BoxFit.cover)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Respuesta del equipo', style: text.labelMedium?.copyWith(color: scheme.primary)),
                          const SizedBox(height: 2),
                          SelectableText(f.reply!, style: text.bodyMedium),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                TextButton.icon(
                  onPressed: onLike,
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                    child: Icon(
                      liked ? Icons.thumb_up_alt_rounded : Icons.thumb_up_alt_outlined,
                      key: ValueKey(liked),
                      size: 18,
                    ),
                  ),
                  label: Text(f.likedBy.isEmpty ? 'Yo también' : '${f.likedBy.length}'),
                ),
                const Spacer(),
                if (me.isAdmin && f.reply == null)
                  TextButton.icon(
                    onPressed: onReply,
                    icon: const Icon(Icons.reply_rounded, size: 18),
                    label: const Text('Responder'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoViewer extends StatelessWidget {
  final Uint8List image;
  final Object tag;
  const _PhotoViewer({required this.image, required this.tag});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: Center(
        child: InteractiveViewer(
          maxScale: 5,
          child: Hero(tag: tag, child: Image.memory(image)),
        ),
      ),
    );
  }
}
