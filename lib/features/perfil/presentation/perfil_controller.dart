import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../domain/tipo_objetivo.dart';

/// Estado de la sección "Mis Objetivos" del perfil.
///
/// Por ahora solo cubre la selección múltiple de objetivos (SCRUM-86). El valor
/// de cada objetivo llega en SCRUM-87 y SCRUM-88, y la persistencia en la tabla
/// `objetivos` en SCRUM-89.
class PerfilController extends ChangeNotifier {
  final Set<TipoObjetivo> _seleccionados = <TipoObjetivo>{};

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
}
