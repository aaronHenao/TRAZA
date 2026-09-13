import 'package:flutter/material.dart';

import '../../utils/validators.dart';
import '../../widgets/auth_widgets.dart';
import '../../widgets/google_logo.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
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

  void _mostrarMensaje(String texto) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  void _onIniciarSesion() {
    // Pinta en rojo los campos vacíos y detiene el envío (criterio 4).
    if (!_formKey.currentState!.validate()) return;

    // TODO(SCRUM-64): iniciar sesión con Supabase.
  }

  @override
  Widget build(BuildContext context) {
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
                'Inicia sesión',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: colorTextoPrincipal,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Ingresa para continuar con tus entrenamientos.',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: colorTextoSecundario,
                ),
              ),
              const SizedBox(height: 28),

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
              const SizedBox(height: 18),

              const EtiquetaCampo('Contraseña'),
              TextFormField(
                controller: _passwordController,
                validator: validarPasswordIngreso,
                obscureText: !_verPassword,
                textInputAction: TextInputAction.done,
                // Tocar "listo" en el teclado equivale a tocar el botón.
                onFieldSubmitted: (_) => _onIniciarSesion(),
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
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  // TODO(SCRUM-65): abrir la recuperación de contraseña.
                  onPressed: () =>
                      _mostrarMensaje('Recuperar contraseña: próximamente'),
                  child: const Text('¿Olvidaste tu contraseña?'),
                ),
              ),
              const SizedBox(height: 12),

              FilledButton(
                onPressed: _onIniciarSesion,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Text('Iniciar sesión'),
              ),
              const SizedBox(height: 18),

              const DivisorO(),
              const SizedBox(height: 18),

              OutlinedButton.icon(
                // TODO: inicio de sesión con Google, HU SCRUM-35.
                onPressed: () => _mostrarMensaje(
                  'Inicio de sesión con Google: próximamente',
                ),
                icon: const GoogleLogo(size: 18),
                label: const Text('Continuar con Google'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: const StadiumBorder(),
                  side: const BorderSide(color: Color(0xFFE3E3E8)),
                  foregroundColor: colorTextoPrincipal,
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 26),

              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    '¿No tienes cuenta? ',
                    style: TextStyle(fontSize: 14, color: colorTextoSecundario),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const RegisterScreen()),
                    ),
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
