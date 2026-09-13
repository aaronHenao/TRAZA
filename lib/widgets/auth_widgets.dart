import 'package:flutter/material.dart';

/// Colores de las pantallas de registro e inicio de sesión.
const colorTextoPrincipal = Color(0xFF16161A);
const colorTextoSecundario = Color(0xFF6B6B73);
const colorTextoSuave = Color(0xFF9A9AA2);
const colorExito = Color(0xFF1E9E5A);

const _colorFondoPantallaGrande = Color(0xFFF0F0F3);
const _colorBordeTarjeta = Color(0xFFE8E8EC);

/// Ancho máximo del formulario: más ancho, los campos se vuelven incómodos.
const _anchoFormulario = 400.0;

/// Desde este tamaño se usa la tarjeta centrada en vez del diseño de celular.
const _breakpointAncho = 600.0;
const _breakpointAlto = 600.0;

/// Estructura común de las pantallas de autenticación.
///
/// En celular, fondo blanco de borde a borde y contenido pegado arriba. En
/// tablet y computador, tarjeta blanca centrada sobre fondo gris.
class AuthLayout extends StatelessWidget {
  const AuthLayout({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Exige ancho Y alto para que un celular acostado siga usando el diseño
    // de celular.
    final pantalla = MediaQuery.sizeOf(context);
    final esPantallaGrande =
        pantalla.width >= _breakpointAncho &&
        pantalla.height >= _breakpointAlto;

    if (!esPantallaGrande) {
      return Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _anchoFormulario),
                child: child,
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _colorFondoPantallaGrande,
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
                border: Border.all(color: _colorBordeTarjeta),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Logo y nombre de la app.
class MarcaTraza extends StatelessWidget {
  const MarcaTraza({super.key});

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
            color: colorTextoPrincipal,
          ),
        ),
      ],
    );
  }
}

/// Texto que va encima de cada campo del formulario.
class EtiquetaCampo extends StatelessWidget {
  const EtiquetaCampo(this.texto, {super.key});

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
          color: colorTextoPrincipal,
        ),
      ),
    );
  }
}

/// Línea con una "o" en el medio, entre el botón principal y el de Google.
class DivisorO extends StatelessWidget {
  const DivisorO({super.key});

  @override
  Widget build(BuildContext context) {
    const linea = Expanded(child: Divider(color: Color(0xFFE3E3E8)));

    return const Row(
      children: [
        linea,
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text('o', style: TextStyle(color: colorTextoSuave)),
        ),
        linea,
      ],
    );
  }
}
