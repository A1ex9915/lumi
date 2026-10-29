import 'package:chatbotmovil/main.dart';
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

  group('Contraseña', () {
    test('acepta 8+ caracteres con un carácter especial', () {
      for (final p in ['Lumi2026!', 'abcdefg#', 'mi clave segura.', r'12345678$']) {
        expect(validatePassword(p), isNull, reason: p);
      }
    });

    test('rechaza menos de 8 caracteres', () {
      expect(validatePassword('Ab1!xyz'), contains('8 caracteres'));
    });

    test('rechaza si no tiene carácter especial', () {
      for (final p in ['Lumi20266', 'abcdefgh', 'Contraseña1', 'ÁÉÍÓÚñññ']) {
        expect(validatePassword(p), contains('carácter especial'), reason: p);
      }
    });

    test('rechaza vacía', () {
      expect(validatePassword(''), isNotNull);
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

    await tester.enterText(find.widgetWithText(TextFormField, 'Nombre'), 'Ana');
    await tester.enterText(find.widgetWithText(TextFormField, 'Correo electrónico'), 'ana@gmail');
    await tester.enterText(find.widgetWithText(TextFormField, 'Contraseña'), 'corta');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirmar contraseña'), 'otra');
    await tester.tap(find.text('Crear cuenta'));
    await tester.pumpAndSettle();

    expect(find.textContaining('no es válido'), findsOneWidget);
    expect(find.textContaining('al menos 8 caracteres'), findsOneWidget);
    expect(find.text('Las contraseñas no coinciden'), findsOneWidget);

    // La lista de requisitos se marca al escribir una contraseña correcta
    await tester.enterText(find.widgetWithText(TextFormField, 'Contraseña'), 'Lumi2026!');
    await tester.pump();
    expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(2));
  });
}
