import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../utils/validators.dart';
import '../../widgets/google_logo.dart';

const _textoPrincipal = Color(0xFF16161A);
const _textoSecundario = Color(0xFF6B6B73);
const _verde = Color(0xFF1E9E5A);
const _fondoPantallaGrande = Color(0xFFF0F0F3);
const _bordeTarjeta = Color(0xFFE8E8EC);

/// Ancho máximo del formulario: más ancho, los campos se vuelven incómodos.
const _anchoFormulario = 400.0;

/// Desde este tamaño se usa la tarjeta centrada en vez del diseño de celular.
const _breakpointAncho = 600.0;
const _breakpointAlto = 600.0;

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _correoController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();

  bool _cargando = false;
  bool _verPassword = false;

  @override
  void dispose() {
    _nombreController.dispose();
    _correoController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _onRegistrar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _cargando = true);

    try {
      final requiereConfirmacion = await _authService.registrar(
        nombre: _nombreController.text.trim(),
        correo: _correoController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;
      _mostrarAlerta(
        'Cuenta creada',
        requiereConfirmacion
            ? 'Te enviamos un correo a ${_correoController.text.trim()}. '
                  'Ábrelo para confirmar tu cuenta antes de iniciar sesión.'
            : 'Ya puedes iniciar sesión con tu correo y contraseña.',
      );
    } on CorreoYaRegistradoException {
      if (!mounted) return;
      _mostrarAlerta(
        'Correo en uso',
        'El correo ingresado ya está asociado a una cuenta',
      );
    } on RegistroException catch (e) {
      if (!mounted) return;
      _mostrarAlerta(e.titulo, e.mensaje);
    } catch (e) {
      // Cualquier error que no venga de Supabase. Se imprime para depurarlo.
      debugPrint('Error inesperado al registrar: $e');
      if (!mounted) return;
      _mostrarAlerta(
        'Algo salió mal',
        'Ocurrió un error inesperado. Inténtalo de nuevo.',
      );
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _mostrarMensaje(String texto) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
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
    // MediaQuery es el equivalente de las media queries de CSS: el tamaño real
    // de la pantalla. Exige ancho Y alto para que un celular acostado (ancho
    // pero bajito) siga usando el diseño de celular.
    final pantalla = MediaQuery.sizeOf(context);
    final esPantallaGrande =
        pantalla.width >= _breakpointAncho &&
        pantalla.height >= _breakpointAlto;

    if (!esPantallaGrande) {
      // Celular: fondo blanco de borde a borde, contenido pegado arriba.
      return Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _anchoFormulario),
                child: _formulario(context),
              ),
            ),
          ),
        ),
      );
    }

    // Tablet y computador: tarjeta blanca centrada sobre fondo gris.
    return Scaffold(
      backgroundColor: _fondoPantallaGrande,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Container(
              constraints: const BoxConstraints(
                maxWidth: _anchoFormulario + 80,
              ),
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _bordeTarjeta),
              ),
              child: _formulario(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _formulario(BuildContext context) {
    final morado = Theme.of(context).colorScheme.primary;

    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Marca(),
          const SizedBox(height: 36),
          const Text(
            'Crea tu cuenta',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: _textoPrincipal,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Regístrate para empezar a registrar tus entrenamientos.',
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: _textoSecundario,
            ),
          ),
          const SizedBox(height: 28),

          const _Etiqueta('Nombre completo'),
          TextFormField(
            controller: _nombreController,
            validator: validarNombre,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(hintText: 'Tu nombre'),
          ),
          const SizedBox(height: 18),

          const _Etiqueta('Correo electrónico'),
          TextFormField(
            controller: _correoController,
            validator: validarCorreo,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(hintText: 'nombre@correo.com'),
          ),
          const SizedBox(height: 18),

          const _Etiqueta('Contraseña'),
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
                  color: _textoSecundario,
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
                _ChecklistPassword(password: valor.text),
          ),
          const SizedBox(height: 22),

          FilledButton(
            onPressed: _cargando ? null : _onRegistrar,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: const StadiumBorder(),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: _cargando
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

          const _DivisorO(),
          const SizedBox(height: 18),

          OutlinedButton.icon(
            // TODO: registro con Google, en su propia HU.
            onPressed: () =>
                _mostrarMensaje('Registro con Google: próximamente'),
            icon: const GoogleLogo(size: 18),
            label: const Text('Registrarte con Google'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: const StadiumBorder(),
              side: const BorderSide(color: Color(0xFFE3E3E8)),
              foregroundColor: _textoPrincipal,
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 26),

          // Wrap y no Row: con letra grande o pantalla angosta,
          // "Inicia sesión" baja de línea en vez de desbordarse.
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                '¿Ya tienes cuenta? ',
                style: TextStyle(fontSize: 14, color: _textoSecundario),
              ),
              GestureDetector(
                // TODO(SCRUM-53): navegar a la pantalla de login.
                onTap: () => _mostrarMensaje('Pantalla de login: pendiente'),
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

class _Marca extends StatelessWidget {
  const _Marca();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.map_outlined, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 10),
        const Text(
          'TRAZA',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
            color: _textoPrincipal,
          ),
        ),
      ],
    );
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        texto,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: _textoPrincipal,
        ),
      ),
    );
  }
}

class _ChecklistPassword extends StatelessWidget {
  const _ChecklistPassword({required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final regla in reglasPassword)
          _ItemRegla(
            texto: regla.descripcion,
            cumplida: regla.cumple(password),
          ),
      ],
    );
  }
}

class _ItemRegla extends StatelessWidget {
  const _ItemRegla({required this.texto, required this.cumplida});

  final String texto;
  final bool cumplida;

  @override
  Widget build(BuildContext context) {
    final color = cumplida ? _verde : const Color(0xFF9A9AA2);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            cumplida ? Icons.check_circle : Icons.check_circle_outline,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 6),
          // Expanded deja que el texto parta en dos líneas si no cabe.
          Expanded(
            child: Text(texto, style: TextStyle(fontSize: 12.5, color: color)),
          ),
        ],
      ),
    );
  }
}

class _DivisorO extends StatelessWidget {
  const _DivisorO();

  @override
  Widget build(BuildContext context) {
    const linea = Expanded(child: Divider(color: Color(0xFFE3E3E8)));

    return const Row(
      children: [
        linea,
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text('o', style: TextStyle(color: Color(0xFF9A9AA2))),
        ),
        linea,
      ],
    );
  }
}
