import 'package:flutter/material.dart';

import '../utils/validators.dart';

/// Colores de las pantallas de registro e inicio de sesión.
const colorTextoPrincipal = Color(0xFF16161A);
const colorTextoSecundario = Color(0xFF6B6B73);
const colorTextoSuave = Color(0xFF9A9AA2);
const colorExito = Color(0xFF1E9E5A);

const _colorFondoPantallaGrande = Color(0xFFF0F0F3);
const _colorBordeTarjeta = Color(0xFFE8E8EC);

/// Ancho máximo del formulario: más ancho, los campos se vuelven incómodos.
const _anchoFormulario = 360.0;

/// Desde este tamaño se usa la tarjeta centrada en vez del diseño de celular.
const _breakpointAncho = 600.0;
const _breakpointAlto = 600.0;

/// Estructura común de las pantallas de autenticación.
///
/// En celular, fondo blanco de borde a borde y contenido centrado. En tablet
/// y computador, tarjeta blanca centrada sobre fondo gris.
class AuthLayout extends StatelessWidget {
  const AuthLayout({super.key, required this.child});

  final Widget child;

  /// Campos un poco más bajos que los del resto de la app: aquí hay muchos
  /// seguidos y la pantalla se ve más despejada.
  static ThemeData _tema(BuildContext context) {
    final tema = Theme.of(context);
    return tema.copyWith(
      inputDecorationTheme: tema.inputDecorationTheme.copyWith(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
        isDense: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Exige ancho Y alto para que un celular acostado siga usando el diseño
    // de celular.
    final pantalla = MediaQuery.sizeOf(context);
    final esPantallaGrande =
        pantalla.width >= _breakpointAncho &&
        pantalla.height >= _breakpointAlto;

    final child = Theme(data: _tema(context), child: this.child);

    if (!esPantallaGrande) {
      return Scaffold(
        body: SafeArea(
          // El contenido va centrado en la pantalla mientras quepa; si no
          // cabe (pantalla pequeña o teclado abierto), se desplaza.
          child: LayoutBuilder(
            builder: (context, restricciones) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: restricciones.maxHeight - 48,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: _anchoFormulario,
                    ),
                    child: child,
                  ),
                ),
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

/// Logo de la marca, centrado. El archivo ya trae el nombre, así que no lleva
/// texto al lado.
class MarcaTraza extends StatelessWidget {
  const MarcaTraza({super.key});

  /// Recortado del original que está al lado (`TRAZA MORADO NOMBRE.png`),
  /// sin los márgenes en blanco que traía y con el fondo transparente.
  static const rutaLogo = 'lib/theme/logos/traza_nombre_morado.png';

  /// Contenido y no cover: el logo es muy apaisado y no se puede recortar.
  static const _ancho = 230.0;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Image.asset(
        rutaLogo,
        width: _ancho,
        fit: BoxFit.contain,
        // Quien no pueda verlo igual sabe en qué app está.
        semanticLabel: 'TRAZA',
      ),
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

/// Las 5 reglas de contraseña, marcadas en verde a medida que se cumplen. Lo
/// usan las pantallas que crean una contraseña: registro y recuperación.
class ChecklistPassword extends StatelessWidget {
  const ChecklistPassword({super.key, required this.password});

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
    final color = cumplida ? colorExito : colorTextoSuave;

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
