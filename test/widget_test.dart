import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:chatbotmovil/main.dart';

void main() {
  // En los tests no hay internet: que google_fonts use la fuente por defecto
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('Muestra la pantalla de login de Lumi sin sesión', (WidgetTester tester) async {
    await tester.pumpWidget(const ChatbotApp());
    expect(find.bySemanticsLabel('Lumi'), findsOneWidget);
    expect(find.text('Entrar'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
  });
}
