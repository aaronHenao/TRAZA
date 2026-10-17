import 'package:flutter/material.dart';

/// Limita el ancho del contenido y lo centra.
///
/// En un teléfono no hace nada: el contenido ya es más estrecho que el tope.
/// En una tableta o un teléfono en horizontal evita que las líneas de texto
/// crucen la pantalla entera y que los campos del formulario queden
/// desproporcionados.
class AnchoContenido extends StatelessWidget {
  const AnchoContenido({required this.child, super.key});

  /// Más allá de esto, un formulario de una columna se lee peor, no mejor.
  static const maximo = 520.0;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maximo),
        child: child,
      ),
    );
  }
}
