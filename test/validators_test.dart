import 'package:chatbotmovil/main.dart';
import 'package:chatbotmovil/models.dart';
import 'package:chatbotmovil/validators.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  group('Correo', () {
    test('acepta correos válidos', () {
      for (final e in ['ana@gmail.com', 'jose.luis+lumi@outlook.com.mx', 'A1ex_99@escuela.edu']) {
        expect(validateEmail(e), isNull, reason: e);
      }
    });

    test('rechaza correos inválidos', () {
      for (final e in ['', 'ana', 'ana@', 'ana@gmail', '@gmail.com', 'ana gmail.com', 'ana@gmail.c', 'a@@b.com']) {
        expect(validateEmail(e), isNotNull, reason: e);
      }
    });

    test('rechaza el dominio interno de usuarios', () {
      expect(validateEmail('pepe@chatbot.invalid'), isNotNull);
    });
  });

  group('Nombre', () {
    test('acepta hasta 60 caracteres', () {
      expect(validateName('Ana'), isNull);
      expect(validateName('a' * 60), isNull);
    });

    test('rechaza vacío o más de 60 caracteres', () {
      expect(validateName('   '), isNotNull);
      expect(validateName('a' * 61), contains('60'));
    });
  });

  group('Usuario', () {
    test('acepta hasta 30 caracteres', () {
      for (final u in ['ana', 'ana_99', 'ana.luz-m', 'a' * 30]) {
        expect(validateUsername(u), isNull, reason: u);
      }
    });

    test('rechaza vacío o más de 30 caracteres', () {
      expect(validateUsername(''), isNotNull);
      expect(validateUsername('a' * 31), contains('30'));
    });

    test('rechaza espacios y arroba', () {
      for (final u in ['ana luz', 'ana@gmail.com']) {
        expect(validateUsername(u), isNotNull, reason: u);
      }
    });
  });

  group('Contraseña', () {
    test('acepta 16+ caracteres con una mayúscula y un número', () {
      for (final p in ['LumiSegura2026ab', 'mi clave Segura 1', 'Ñandú con 16 letras']) {
        expect(validatePassword(p), isNull, reason: p);
      }
    });

    test('rechaza menos de 16 caracteres', () {
      expect(validatePassword('Abcdefghijklmn1'), contains('16 caracteres'));
    });

    test('rechaza si no tiene mayúscula', () {
      expect(validatePassword('abcdefghijklmnop1'), contains('mayúscula'));
    });

    test('rechaza si no tiene número', () {
      expect(validatePassword('Abcdefghijklmnopq'), contains('número'));
    });

    test('rechaza vacía', () {
      expect(validatePassword(''), isNotNull);
    });
  });

  group('Historial', () {
    final chats = [
      Conversation(id: '1', title: 'Receta de pan', favorite: true),
      Conversation(id: '2', title: 'Tarea de física'),
      Conversation(id: '3', title: 'Física cuántica', favorite: true),
    ];

    test('separa las favoritas conservando el orden', () {
      final split = splitConversations(chats);
      expect(split.favorites.map((c) => c.id), ['1', '3']);
      expect(split.others.map((c) => c.id), ['2']);
    });

    test('busca por título sin distinguir mayúsculas', () {
      final split = splitConversations(chats, query: ' FÍSICA ');
      expect(split.favorites.map((c) => c.id), ['3']);
      expect(split.others.map((c) => c.id), ['2']);
    });
  });

  testWidgets('El registro valida correo, contraseña y confirmación', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const ChatbotApp());

    await tester.tap(find.text('¿No tienes cuenta? Regístrate'));
    await tester.pumpAndSettle();
    expect(find.text('Correo electrónico'), findsOneWidget);
    expect(find.text('Confirmar contraseña'), findsOneWidget);

    // El nombre y el usuario no dejan escribir más de lo permitido
    await tester.enterText(find.widgetWithText(TextFormField, 'Nombre'), 'a' * 70);
    await tester.pump();
    expect(find.text('a' * 60), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Usuario'), 'u' * 40);
    await tester.pump();
    expect(find.text('u' * 30), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Usuario'), 'ana luz');
    await tester.enterText(find.widgetWithText(TextFormField, 'Correo electrónico'), 'ana@gmail');
    await tester.enterText(find.widgetWithText(TextFormField, 'Contraseña'), 'corta');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirmar contraseña'), 'otra');
    await tester.tap(find.text('Crear cuenta'));
    await tester.pumpAndSettle();

    expect(find.textContaining('no es válido'), findsOneWidget);
    expect(find.textContaining('Solo letras, números'), findsOneWidget);
    expect(find.textContaining('al menos 16 caracteres'), findsOneWidget);
    expect(find.text('Las contraseñas no coinciden'), findsOneWidget);

    // La lista de requisitos se marca al escribir una contraseña correcta
    await tester.enterText(find.widgetWithText(TextFormField, 'Contraseña'), 'LumiSegura2026ab');
    await tester.pump();
    expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(3));
  });
}
