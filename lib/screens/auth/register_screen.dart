import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/estado_registro.dart';
import '../../services/registro_provider.dart';
import '../../utils/validators.dart';
import '../../widgets/auth_widgets.dart';
import '../../widgets/boton_google.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _correoController = TextEditingController();
  final _passwordController = TextEditingController();

  // Estado solo visual, que no le importa a nadie fuera de esta pantalla:
  // se queda aquí con setState en vez de ir al notifier.
  bool _verPassword = false;

  @override
  void dispose() {
    _nombreController.dispose();
    _correoController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onRegistrar() {
    if (!_formKey.currentState!.validate()) return;

    // ref.read y no ref.watch: es una acción, se ejecuta una vez al tocar.
    ref
        .read(registroProvider.notifier)
        .registrar(
          nombre: _nombreController.text.trim(),
          correo: _correoController.text.trim(),
          password: _passwordController.text,
        );
  }

  /// Reacciona a cada cambio de fase. Se registra con `ref.listen` en build.
  void _alCambiarRegistro(EstadoRegistro? anterior, EstadoRegistro actual) {
    switch (actual.fase) {
      case FaseRegistro.exito:
        _mostrarExitoYRedirigir(actual);
      case FaseRegistro.error:
        _mostrarAlerta(actual.tituloError!, actual.mensajeError!);
      case FaseRegistro.inicial || FaseRegistro.enviando:
        break;
    }
  }

  Future<void> _mostrarExitoYRedirigir(EstadoRegistro estado) async {
    await _mostrarAlerta(
      'Cuenta creada',
      estado.requiereConfirmacion
          ? 'Te enviamos un correo a ${estado.correo}. '
                'Ábrelo para confirmar tu cuenta antes de iniciar sesión.'
          : 'Ya puedes iniciar sesión con tu correo y contraseña.',
    );

    if (!mounted) return;
    // go: el formulario ya se usó, atrás no debe volver a él.
    context.go('/login');
  }

  Future<void> _mostrarAlerta(String titulo, String mensaje) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titulo),
        content: Text(mensaje),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ref.listen no redibuja: ejecuta la función cada vez que cambia el estado.
    // Es el lugar para efectos de una sola vez, como alertas y navegación.
    ref.listen(registroProvider, _alCambiarRegistro);

    return AuthLayout(child: _formulario(context));
  }

  Widget _formulario(BuildContext context) {
    final morado = Theme.of(context).colorScheme.primary;
    // ref.watch sí redibuja: el botón cambia a spinner mientras se envía.
    final enviando = ref.watch(registroProvider).enviando;

    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const MarcaTraza(),
          const SizedBox(height: 36),
          const Text(
            'Crea tu cuenta',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: colorTextoPrincipal,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Regístrate para empezar a registrar tus entrenamientos.',
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: colorTextoSecundario,
            ),
          ),
          const SizedBox(height: 28),

          const EtiquetaCampo('Nombre completo'),
          TextFormField(
            controller: _nombreController,
            validator: validarNombre,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(hintText: 'Tu nombre'),
          ),
          const SizedBox(height: 18),

          const EtiquetaCampo('Correo electrónico'),
          TextFormField(
            controller: _correoController,
            validator: validarCorreo,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(hintText: 'nombre@correo.com'),
          ),
          const SizedBox(height: 18),

          const EtiquetaCampo('Contraseña'),
          TextFormField(
            controller: _passwordController,
            validator: validarPassword,
            obscureText: !_verPassword,
            decoration: InputDecoration(
              hintText: 'Crea una contraseña',
              suffixIcon: IconButton(
                icon: Icon(
                  _verPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: colorTextoSecundario,
                ),
                onPressed: () => setState(() => _verPassword = !_verPassword),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Se redibuja solo el checklist en cada tecla, no la pantalla.
          ValueListenableBuilder(
            valueListenable: _passwordController,
            builder: (context, valor, _) =>
                ChecklistPassword(password: valor.text),
          ),
          const SizedBox(height: 22),

          FilledButton(
            onPressed: enviando ? null : _onRegistrar,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: const StadiumBorder(),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: enviando
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Crear cuenta'),
          ),
          const SizedBox(height: 18),

          const DivisorO(),
          const SizedBox(height: 18),

          const BotonGoogle(texto: 'Registrarte con Google'),
          const SizedBox(height: 26),

          // Wrap y no Row: con letra grande o pantalla angosta,
          // "Inicia sesión" baja de línea en vez de desbordarse.
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                '¿Ya tienes cuenta? ',
                style: TextStyle(fontSize: 14, color: colorTextoSecundario),
              ),
              GestureDetector(
                onTap: () => context.go('/login'),
                child: Text(
                  'Inicia sesión',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: morado,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
