import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/estado_login.dart';
import '../../services/login_provider.dart';
import '../../utils/validators.dart';
import '../../widgets/auth_widgets.dart';
import '../../widgets/boton_google.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _correoController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _verPassword = false;

  @override
  void dispose() {
    _correoController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onIniciarSesion() {
    // Pinta en rojo los campos vacíos y detiene el envío (criterio 4).
    if (!_formKey.currentState!.validate()) return;

    ref
        .read(loginProvider.notifier)
        .iniciarSesion(
          correo: _correoController.text.trim(),
          password: _passwordController.text,
        );
  }

  /// Reacciona a cada cambio de fase. Se registra con `ref.listen` en build.
  void _alCambiarLogin(EstadoLogin? anterior, EstadoLogin actual) {
    switch (actual.fase) {
      case FaseLogin.exito:
        // SCRUM-66 y SCRUM-81. go: con la sesión iniciada, atrás no vuelve
        // al login. Quien no ha terminado Perfil y Permisos empieza por ahí.
        context.go(actual.requiereOnboarding ? '/perfil' : '/inicio');
      case FaseLogin.credencialesInvalidas:
        _mostrarCredencialesInvalidas();
      case FaseLogin.error:
        _mostrarAlerta(actual.tituloError!, actual.mensajeError!);
      case FaseLogin.inicial || FaseLogin.enviando:
        break;
    }
  }

  /// Criterios 2 y 3: mismo mensaje para correo no registrado y contraseña
  /// incorrecta, con acceso directo a recuperar la contraseña.
  Future<void> _mostrarCredencialesInvalidas() async {
    final quiereRecuperar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Credenciales no válidas'),
        content: const Text('El correo o la contraseña no son correctos.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Recuperar contraseña'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );

    // Nulo si el diálogo se cerró tocando fuera de él.
    if (quiereRecuperar != true || !mounted) return;
    _irARecuperarPassword();
  }

  /// push y no go: desde la recuperación se puede volver al login.
  void _irARecuperarPassword() {
    context.push('/recuperar', extra: _correoController.text.trim());
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
    // listen: alertas, una vez por cambio. watch: el spinner, que redibuja.
    ref.listen(loginProvider, _alCambiarLogin);
    final enviando = ref.watch(loginProvider).enviando;

    return AuthLayout(
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const MarcaTraza(),
              const SizedBox(height: 36),
              const Text(
                'Ingresa para continuar con tus entrenamientos.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: colorTextoSecundario,
                ),
              ),
              const SizedBox(height: 26),

              const EtiquetaCampo('Correo electrónico'),
              TextFormField(
                controller: _correoController,
                validator: validarCorreo,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                  hintText: 'nombre@correo.com',
                ),
              ),
              const SizedBox(height: 16),

              const EtiquetaCampo('Contraseña'),
              TextFormField(
                controller: _passwordController,
                validator: validarPasswordIngreso,
                obscureText: !_verPassword,
                textInputAction: TextInputAction.done,
                // Tocar "listo" en el teclado equivale a tocar el botón.
                onFieldSubmitted: (_) {
                  if (!enviando) _onIniciarSesion();
                },
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  hintText: 'Tu contraseña',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _verPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: colorTextoSecundario,
                    ),
                    onPressed: () =>
                        setState(() => _verPassword = !_verPassword),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _irARecuperarPassword,
                  child: const Text('¿Olvidaste tu contraseña?'),
                ),
              ),
              const SizedBox(height: 10),

              FilledButton(
                onPressed: enviando ? null : _onIniciarSesion,
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
                    : const Text('Iniciar sesión'),
              ),
              const SizedBox(height: 16),

              const DivisorO(),
              const SizedBox(height: 16),

              const BotonGoogle(texto: 'Continuar con Google'),
              const SizedBox(height: 22),

              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    '¿No tienes cuenta? ',
                    style: TextStyle(fontSize: 14, color: colorTextoSecundario),
                  ),
                  GestureDetector(
                    onTap: () => context.go('/registro'),
                    child: Text(
                      'Regístrate',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
