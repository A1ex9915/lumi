import 'config.dart';

final _emailRe = RegExp(r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}$");
final _usernameRe = RegExp(r'^[A-Za-z0-9._-]+$');

/// Máximo de caracteres del nombre.
const nameMaxLength = 60;

/// Máximo de caracteres del usuario.
const usernameMaxLength = 30;

/// Mínimo de caracteres de la contraseña.
const passwordMinLength = 16;

bool isValidEmail(String email) => _emailRe.hasMatch(email.trim());

bool hasMinLength(String password) => password.length >= passwordMinLength;

bool hasUppercase(String password) => RegExp(r'[A-ZÁÉÍÓÚÜÑ]').hasMatch(password);

bool hasDigit(String password) => RegExp(r'[0-9]').hasMatch(password);

String? validateName(String? value) {
  final v = value?.trim() ?? '';
  if (v.isEmpty) return 'Ingresa tu nombre';
  if (v.runes.length > nameMaxLength) return 'Máximo $nameMaxLength caracteres';
  return null;
}

String? validateUsername(String? value) {
  final v = value?.trim() ?? '';
  if (v.isEmpty) return 'Ingresa un usuario';
  if (v.length > usernameMaxLength) return 'Máximo $usernameMaxLength caracteres';
  if (!_usernameRe.hasMatch(v)) return 'Solo letras, números, punto, guion y guion bajo';
  return null;
}

String? validateEmail(String? value) {
  final v = value?.trim() ?? '';
  if (v.isEmpty) return 'Ingresa tu correo';
  if (!isValidEmail(v)) return 'Ese correo no es válido (ej.: nombre@gmail.com)';
  if (v.toLowerCase().endsWith('@$usernameEmailDomain')) return 'Usa un correo real';
  return null;
}

String? validatePassword(String? value) {
  final v = value ?? '';
  if (v.isEmpty) return 'Ingresa una contraseña';
  if (!hasMinLength(v)) return 'Debe tener al menos $passwordMinLength caracteres';
  if (!hasUppercase(v)) return 'Debe incluir al menos una mayúscula';
  if (!hasDigit(v)) return 'Debe incluir al menos un número';
  return null;
}
