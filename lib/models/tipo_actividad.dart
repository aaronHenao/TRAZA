import 'package:flutter/foundation.dart';

/// Tipo de actividad del catálogo `tipos_actividad`
/// (`supabase/migrations/0001_init_sprint1.sql`).
///
/// Dos tipos son iguales si tienen el mismo [nombre], que en la tabla es
/// `unique`. Así la selección del usuario sobrevive a una recarga del catálogo.
@immutable
class TipoActividad {
  const TipoActividad({required this.id, required this.nombre});

  /// Id de la fila en `tipos_actividad`. Es null en el [catalogoLocal]: sin
  /// sesión la tabla no se puede leer, y sin id tampoco se puede crear un
  /// entrenamiento, que es justo lo que se quiere mientras no haya login.
  final String? id;

  final String nombre;

  /// Orden en que el prototipo muestra los chips. Los tipos que no estén aquí
  /// van al final, por nombre.
  static const ordenPreferido = ['Correr', 'Trote', 'Caminar'];

  /// Los tipos que siembra la migración, sin id. Se usan mientras no hay
  /// sesión.
  static final catalogoLocal = List<TipoActividad>.unmodifiable([
    for (final nombre in ordenPreferido) TipoActividad(id: null, nombre: nombre),
  ]);

  @override
  bool operator ==(Object other) =>
      other is TipoActividad && other.nombre == nombre;

  @override
  int get hashCode => nombre.hashCode;

  @override
  String toString() => 'TipoActividad($nombre)';
}

/// Ordena [tipos] como el prototipo: primero los de
/// [TipoActividad.ordenPreferido] y después el resto, alfabéticamente.
List<TipoActividad> ordenarTiposActividad(Iterable<TipoActividad> tipos) {
  int posicion(TipoActividad tipo) {
    final indice = TipoActividad.ordenPreferido.indexOf(tipo.nombre);
    return indice == -1 ? TipoActividad.ordenPreferido.length : indice;
  }

  return tipos.toList()..sort((a, b) {
    final porOrden = posicion(a).compareTo(posicion(b));
    return porOrden != 0 ? porOrden : a.nombre.compareTo(b.nombre);
  });
}
