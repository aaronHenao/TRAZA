import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../domain/tipo_objetivo.dart';
import '../domain/validacion_objetivo.dart';

/// Estado de la sección "Mis Objetivos" del perfil.
///
/// Cubre la selección múltiple (SCRUM-86) y el valor de cada objetivo
/// (SCRUM-87 distancia, SCRUM-88 frecuencia). La escritura en la tabla
/// `objetivos` es SCRUM-89.
class PerfilController extends ChangeNotifier {
  final Set<TipoObjetivo> _seleccionados = <TipoObjetivo>{};

  /// Texto crudo de cada campo. Se conserva aunque el objetivo se desmarque,
  /// para que al volver a marcarlo reaparezca lo que el usuario había escrito.
  final Map<TipoObjetivo, String> _textos = {
    for (final tipo in TipoObjetivo.values)
      tipo: formatearValorObjetivo(tipo.valorPorDefecto),
  };

  UnmodifiableSetView<TipoObjetivo> get seleccionados =>
      UnmodifiableSetView(_seleccionados);

  bool get sinObjetivos => _seleccionados.isEmpty;

  bool estaSeleccionado(TipoObjetivo tipo) => _seleccionados.contains(tipo);

  /// Marca o desmarca un objetivo. Se pueden tener varios activos a la vez.
  void alternar(TipoObjetivo tipo) {
    if (!_seleccionados.remove(tipo)) {
      _seleccionados.add(tipo);
    }
    notifyListeners();
  }

  String textoDe(TipoObjetivo tipo) => _textos[tipo]!;

  /// Mensaje de error del valor actual, o null si es válido.
  String? errorDe(TipoObjetivo tipo) =>
      validarValorObjetivo(tipo, textoDe(tipo));

  /// Valor listo para guardar, o null si el texto actual no es válido.
  num? valorDe(TipoObjetivo tipo) => errorDe(tipo) == null
      ? interpretarValorObjetivo(tipo, textoDe(tipo))
      : null;

  void actualizarValor(TipoObjetivo tipo, String texto) {
    if (_textos[tipo] == texto) return;
    _textos[tipo] = texto;
    notifyListeners();
  }

  /// True si algún objetivo marcado tiene un valor que no se puede guardar.
  bool get hayValoresInvalidos =>
      _seleccionados.any((tipo) => errorDe(tipo) != null);
}
