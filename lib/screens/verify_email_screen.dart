import 'dart:async';

import 'package:flutter/material.dart';

import '../api_service.dart';
import '../theme.dart';

/// Tras registrarse con correo: pide tocar el enlace del correo de verificación antes de entrar.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> with WidgetsBindingObserver {
  final _api = ApiService.instance;
  bool _checking = false;
  String? _message;
  int _cooldown = 60; // segundos para poder reenviar (el primer correo se acaba de enviar)
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startCooldown();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  // Al volver a la app desde el correo, se comprueba solo
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check(silent: true);
  }

  void _startCooldown([int seconds = 60]) {
    _timer?.cancel();
    setState(() => _cooldown = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  Future<void> _check({bool silent = false}) async {
    if (_checking) return;
    setState(() {
      _checking = true;
      if (!silent) _message = null;
    });
    try {
      final ok = await _api.checkEmailVerified();
      if (!ok && !silent && mounted) {
        setState(() => _message = 'Todavía no aparece verificado. Toca el enlace del correo y vuelve a intentarlo.');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (_) {
      if (!silent && mounted) setState(() => _message = 'No se pudo comprobar. Revisa tu conexión.');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _resend() async {
    try {
      await _api.resendVerificationEmail();
      _startCooldown();
      if (mounted) setState(() => _message = 'Te enviamos otro correo. Revisa también la carpeta de spam.');
    } on ApiException catch (e) {
      if (mounted) setState(() => _message = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final email = _api.pendingEmail ?? '';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: ClipOval(child: Image.asset(LumiImages.curioso, height: 140, width: 140, fit: BoxFit.cover)),
                  ),
                  const SizedBox(height: 20),
                  Text('¡Revisa tu correo!', textAlign: TextAlign.center, style: text.headlineSmall),
                  const SizedBox(height: 10),
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: 'Te enviamos un enlace de verificación a\n'),
                        TextSpan(
                          text: email,
                          style: TextStyle(fontWeight: FontWeight.bold, color: scheme.primary),
                        ),
                        const TextSpan(text: '\nTócalo para activar tu cuenta y conocer a Lumi.'),
                      ],
                    ),
                    textAlign: TextAlign.center,
                    style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '¿No te llega? Revisa la carpeta de spam o de promociones.',
                    textAlign: TextAlign.center,
                    style: text.bodySmall?.copyWith(color: scheme.outline),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.primary),
                    ),
                  ],
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: _checking ? null : () => _check(),
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                    icon: _checking
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.mark_email_read_outlined),
                    label: const Text('Ya lo verifiqué'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _cooldown > 0 ? null : _resend,
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    icon: const Icon(Icons.forward_to_inbox_outlined),
                    label: Text(_cooldown > 0 ? 'Reenviar correo ($_cooldown s)' : 'Reenviar correo'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(onPressed: _api.logout, child: const Text('Usar otra cuenta')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
