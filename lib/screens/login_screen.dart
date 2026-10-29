import 'package:flutter/material.dart';

import '../api_service.dart';
import '../theme.dart';
import '../validators.dart';

/// Pantalla de inicio de sesión y registro (manual con correo o con Google).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController(); // al entrar: correo o usuario
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _registerMode = false;
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Para que la lista de requisitos de la contraseña se actualice mientras se escribe
    _password.addListener(() {
      if (_registerMode) setState(() {});
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _toggleMode() {
    setState(() {
      _registerMode = !_registerMode;
      _error = null;
      _confirm.clear();
    });
    _formKey.currentState?.reset();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ApiService.instance;
      if (_registerMode) {
        await api.registerWithEmail(_name.text.trim(), _email.text.trim(), _password.text);
      } else {
        await api.login(_email.text.trim(), _password.text);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _googleSignIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Si el usuario cierra el selector de cuentas simplemente no pasa nada
      await ApiService.instance.loginWithGoogle();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Lumi saludando con el logo encima
                    Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.bottomCenter,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(32),
                          // Proporción de la ilustración: así no se recorta el globo "¡Hola! Soy Lumi"
                          child: AspectRatio(
                            aspectRatio: 593 / 366,
                            child: Image.asset(LumiImages.hero, fit: BoxFit.cover),
                          ),
                        ),
                        Positioned(bottom: -42, child: Image.asset(LumiImages.logo, height: 96, semanticLabel: 'Lumi')),
                      ],
                    ),
                    const SizedBox(height: 52),
                    Text(
                      _registerMode ? 'Crea tu cuenta y conoce a Lumi' : 'Tu asistente que siempre está ahí',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 24),
                    if (_registerMode) ...[
                      TextFormField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(labelText: 'Nombre', prefixIcon: Icon(Icons.badge_outlined)),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Ingresa tu nombre' : null,
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      controller: _email,
                      autocorrect: false,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: _registerMode ? 'Correo electrónico' : 'Correo o usuario',
                        prefixIcon: Icon(_registerMode ? Icons.email_outlined : Icons.alternate_email),
                      ),
                      validator: _registerMode
                          ? validateEmail
                          : (v) => v == null || v.trim().isEmpty ? 'Ingresa tu correo o usuario' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      textInputAction: _registerMode ? TextInputAction.next : TextInputAction.done,
                      onFieldSubmitted: (_) => _registerMode ? null : _submit(),
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: _obscure ? 'Mostrar contraseña' : 'Ocultar contraseña',
                          icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: _registerMode
                          ? validatePassword
                          : (v) => v == null || v.isEmpty ? 'Ingresa tu contraseña' : null,
                    ),
                    if (_registerMode) ...[
                      const SizedBox(height: 10),
                      _PasswordChecklist(password: _password.text),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _confirm,
                        obscureText: _obscure,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: const InputDecoration(
                          labelText: 'Confirmar contraseña',
                          prefixIcon: Icon(Icons.lock_reset_outlined),
                        ),
                        validator: (v) => v != _password.text ? 'Las contraseñas no coinciden' : null,
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: TextStyle(color: scheme.error),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                      child: _loading
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_registerMode ? 'Crear cuenta' : 'Entrar'),
                    ),
                    if (ApiService.instance.firebaseReady) ...[
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          const Expanded(child: Divider()),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text('o', style: TextStyle(color: scheme.onSurfaceVariant)),
                          ),
                          const Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: 20),
                      OutlinedButton.icon(
                        onPressed: _loading ? null : _googleSignIn,
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                        icon: const Text(
                          'G',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF4285F4)),
                        ),
                        label: const Text('Continuar con Google'),
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _loading ? null : _toggleMode,
                      child: Text(_registerMode ? '¿Ya tienes cuenta? Inicia sesión' : '¿No tienes cuenta? Regístrate'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Requisitos de la contraseña que se marcan ✓ mientras se escribe.
class _PasswordChecklist extends StatelessWidget {
  final String password;
  const _PasswordChecklist({required this.password});

  @override
  Widget build(BuildContext context) {
    final rules = [
      ('Al menos $passwordMinLength caracteres', hasMinLength(password)),
      ('Al menos un carácter especial (! @ # \$ % & * …)', hasSpecialChar(password)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (label, ok) in rules)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 2, bottom: 2),
            child: Row(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                  child: Icon(
                    ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                    key: ValueKey(ok),
                    size: 18,
                    color: ok ? Colors.green : Theme.of(context).colorScheme.outline,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      color: ok ? Colors.green : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
