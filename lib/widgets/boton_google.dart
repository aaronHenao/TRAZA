import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/estado_login.dart';
import '../services/inicio_google_provider.dart';
import 'auth_widgets.dart';
import 'google_logo.dart';

/// Botón "Continuar con Google" completo: inicia sesión, muestra el spinner
/// y reacciona al resultado. Login y registro solo lo colocan.
class BotonGoogle extends ConsumerWidget {
  const BotonGoogle({super.key, required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(inicioGoogleProvider, (anterior, actual) {
      switch (actual.fase) {
        case FaseLogin.exito:
          // TODO(SCRUM-60, SCRUM-70): después del merge con develop, ir a
          // Perfil si es el primer acceso o a Inicio si ya tenía cuenta.
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sesión iniciada con Google')),
          );
        case FaseLogin.error:
          showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(actual.tituloError!),
              content: Text(actual.mensajeError!),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Entendido'),
                ),
              ],
            ),
          );
        case FaseLogin.inicial ||
            FaseLogin.enviando ||
            FaseLogin.credencialesInvalidas:
          break;
      }
    });
    final conectando = ref.watch(inicioGoogleProvider).enviando;

    return OutlinedButton.icon(
      onPressed: conectando
          ? null
          : () => ref.read(inicioGoogleProvider.notifier).iniciar(),
      icon: conectando
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const GoogleLogo(size: 18),
      label: Text(texto),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: const StadiumBorder(),
        side: const BorderSide(color: Color(0xFFE3E3E8)),
        foregroundColor: colorTextoPrincipal,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    );
  }
}
