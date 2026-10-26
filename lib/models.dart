import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? _date(Object? value) => value is Timestamp ? value.toDate() : null;

class User {
  final String id; // uid de Firebase
  final String username;
  final String name;
  final String role;
  final String? email;
  final String provider; // 'password' | 'google'
  final bool disabled;

  User({
    required this.id,
    required this.username,
    required this.name,
    required this.role,
    this.email,
    this.provider = 'password',
    this.disabled = false,
  });

  bool get isAdmin => role == 'admin';
  bool get isGoogle => provider == 'google';

  factory User.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final j = doc.data()!;
    return User(
      id: doc.id,
      username: j['username'] as String,
      name: j['name'] as String,
      role: j['role'] as String,
      email: j['email'] as String?,
      provider: j['provider'] as String? ?? 'password',
      disabled: j['disabled'] as bool? ?? false,
    );
  }
}

class Conversation {
  final String id;
  final String title;
  final DateTime? updatedAt;

  Conversation({required this.id, required this.title, this.updatedAt});

  factory Conversation.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final j = doc.data()!;
    return Conversation(id: doc.id, title: j['title'] as String, updatedAt: _date(j['updatedAt']));
  }
}

class ChatMessage {
  final String? id;
  final String role; // 'user' | 'assistant'
  final String content;
  final DateTime createdAt;

  /// Foto adjunta (JPEG ya comprimido), solo en mensajes del usuario.
  final Uint8List? image;

  /// "Me gusta" en respuestas de Lumi (se puede cambiar después).
  bool liked;

  ChatMessage({this.id, required this.role, required this.content, DateTime? createdAt, this.image, this.liked = false})
    : createdAt = createdAt ?? DateTime.now();

  bool get isUser => role == 'user';

  factory ChatMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final j = doc.data()!;
    return ChatMessage(
      id: doc.id,
      role: j['role'] as String,
      content: j['content'] as String,
      createdAt: _date(j['createdAt']),
      image: (j['image'] as Blob?)?.bytes,
      liked: j['liked'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
    'role': role,
    'content': content,
    'createdAt': Timestamp.fromDate(createdAt),
    if (image != null) 'image': Blob(image!),
  };
}

/// Comentario de un tester (colección `feedback`).
class TesterFeedback {
  final String id;
  final String uid;
  final String name;
  final int rating; // 1-5
  final String type; // 'bug' | 'idea' | 'love'
  final String text;
  final Uint8List? image;
  final DateTime? createdAt;
  final List<String> likedBy;
  final String? reply;
  final bool resolved;

  TesterFeedback({
    required this.id,
    required this.uid,
    required this.name,
    required this.rating,
    required this.type,
    required this.text,
    this.image,
    this.createdAt,
    this.likedBy = const [],
    this.reply,
    this.resolved = false,
  });

  factory TesterFeedback.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final j = doc.data()!;
    return TesterFeedback(
      id: doc.id,
      uid: j['uid'] as String,
      name: j['name'] as String,
      rating: (j['rating'] as num).toInt(),
      type: j['type'] as String,
      text: j['text'] as String,
      image: (j['image'] as Blob?)?.bytes,
      createdAt: _date(j['createdAt']),
      likedBy: List<String>.from(j['likedBy'] as List? ?? const []),
      reply: j['reply'] as String?,
      resolved: j['resolved'] as bool? ?? false,
    );
  }
}
