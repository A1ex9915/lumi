import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Paleta de Lumi (tomada del logo y las ilustraciones).
abstract final class LumiColors {
  static const purple = Color(0xFF8B6CF6); // letras del logo / cuerpo del robot
  static const purpleLight = Color(0xFFC9B8FF);
  static const lilac = Color(0xFFEAE4FF); // burbujas del bot
  static const navy = Color(0xFF1E1A4A); // contorno del logo / pantalla del robot
  static const cyan = Color(0xFF3DD5F0); // antena, ojos y línea del logo
  static const heart = Color(0xFFFF6FA0); // corazones de las ilustraciones
  static const lavender = Color(0xFFF2F0FC); // fondo de las ilustraciones
  static const nightBg = Color(0xFF17143A); // modo oscuro (escena 'Siempre está ahí')
  static const nightSurface = Color(0xFF242056);
}

/// Imágenes de Lumi (recortadas de la hoja de marca, en assets/lumi/).
abstract final class LumiImages {
  static const _dir = 'assets/lumi';
  static const logo = '$_dir/logo.png';
  static const icon = '$_dir/icon_launcher.png';
  static const hero = '$_dir/hero.png';
  static const saluda = '$_dir/saluda.png';
  static const feliz = '$_dir/feliz.png';
  static const curioso = '$_dir/curioso.png';
  static const emocionado = '$_dir/emocionado.png';
  static const triste = '$_dir/triste.png';
  static const pensando = '$_dir/pensando.png';
  static const dormido = '$_dir/dormido.png';
  static const amor = '$_dir/amor.png';
  static const ayuda = '$_dir/ayuda.png';
  static const dudas = '$_dir/dudas.png';
  static const ideas = '$_dir/ideas.png';
  static const aprende = '$_dir/aprende.png';
  static const cuidarte = '$_dir/cuidarte.png';
  static const siempre = '$_dir/siempre.png';
}

ThemeData lumiTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: LumiColors.purple, brightness: brightness).copyWith(
    primary: dark ? LumiColors.purpleLight : LumiColors.purple,
    onPrimary: dark ? LumiColors.navy : Colors.white,
    secondary: LumiColors.cyan,
    tertiary: LumiColors.cyan,
    surface: dark ? LumiColors.nightBg : LumiColors.lavender,
    onSurface: dark ? const Color(0xFFEEEBFF) : LumiColors.navy,
    surfaceContainerLow: dark ? LumiColors.nightSurface : Colors.white,
    surfaceContainerHigh: dark ? LumiColors.nightSurface : Colors.white,
    surfaceContainerHighest: dark ? const Color(0xFF302A6B) : LumiColors.lilac,
    outlineVariant: dark ? const Color(0xFF3D3780) : LumiColors.purpleLight,
  );

  // Textos con Nunito y títulos con Fredoka (redondeada como el logo)
  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surface,
    fontFamily: GoogleFonts.nunito().fontFamily,
  );
  final text = base.textTheme.apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
  TextStyle? rounded(TextStyle? s) =>
      s?.merge(GoogleFonts.fredoka(fontWeight: FontWeight.w600, color: scheme.onSurface));

  return base.copyWith(
    textTheme: text.copyWith(
      headlineMedium: rounded(text.headlineMedium),
      headlineSmall: rounded(text.headlineSmall),
      titleLarge: rounded(text.titleLarge),
      titleMedium: rounded(text.titleMedium),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: const StadiumBorder(),
        textStyle: GoogleFonts.fredoka(fontSize: 17, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant, width: 1.5),
        foregroundColor: scheme.onSurface,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    drawerTheme: DrawerThemeData(backgroundColor: scheme.surface),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
