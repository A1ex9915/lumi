import 'config.dart';

final _emailRe = RegExp(r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}$");

/// Mínimo de caracteres de la contraseña.
const passwordMinLength = 8;

bool isValidEmail(String email) => _emailRe.hasMatch(email.trim());

bool hasMinLength(String password) => password.length >= passwordMinLength;

/// Carácter especial: cualquier cosa que no sea letra, número o espacio (p. ej. ! @ # \$ % & * . - _).
bool hasSpecialChar(String password) => RegExp(r'[^A-Za-z0-9\sÁÉÍÓÚÜÑáéíóúüñ]').hasMatch(password);

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
  if (!hasSpecialChar(v)) return 'Debe incluir al menos un carácter especial (! @ # \$ % & *…)';
  return null;
}
