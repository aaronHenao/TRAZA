import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../data/objetivos_repository.dart';
import '../domain/tipo_objetivo.dart';
import '../domain/validacion_objetivo.dart';

/// Estado de la sección "Mis Objetivos" del perfil.
///
/// Cubre la selección múltiple (SCRUM-86), el valor de cada objetivo
/// (SCRUM-87 distancia, SCRUM-88 frecuencia) y el guardado en la tabla
/// `objetivos` (SCRUM-89).
class PerfilController extends ChangeNotifier {
  PerfilController({ObjetivosRepository? repositorio})
    : _repositorio = repositorio ?? const SupabaseObjetivosRepository();

  final ObjetivosRepository _repositorio;

  final Set<TipoObjetivo> _seleccionados = <TipoObjetivo>{};

  /// Texto crudo de cada campo. Se conserva aunque el objetivo se desmarque,
  /// para que al volver a marcarlo reaparezca lo que el usuario había escrito.
  final Map<TipoObjetivo, String> _textos = {
    for (final tipo in TipoObjetivo.values)
      tipo: formatearValorObjetivo(tipo.valorPorDefecto),
  };

  bool _guardando = false;

  UnmodifiableSetView<TipoObjetivo> get seleccionados =>
      UnmodifiableSetView(_seleccionados);

  bool get sinObjetivos => _seleccionados.isEmpty;

  bool get guardando => _guardando;

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

  /// Objetivos marcados con su valor, tal como se van a persistir.
  Map<TipoObjetivo, num> get objetivosAGuardar => {
    for (final tipo in _seleccionados) tipo: ?valorDe(tipo),
  };

  bool get puedeGuardar => !sinObjetivos && !hayValoresInvalidos && !_guardando;

  /// Guarda los objetivos marcados en el perfil del usuario.
  ///
  /// Devuelve null si salió bien, o el mensaje de error a mostrar.
  Future<String?> guardarObjetivos() async {
    if (sinObjetivos) return 'Selecciona al menos un objetivo';
    if (hayValoresInvalidos) return 'Revisa los valores de tus objetivos';

    _guardando = true;
    notifyListeners();
    try {
      await _repositorio.guardar(objetivosAGuardar);
      return null;
    } on SesionRequeridaException {
      return 'Inicia sesión para guardar tus objetivos';
    } catch (error) {
      debugPrint('No se pudieron guardar los objetivos: $error');
      return 'No se pudieron guardar tus objetivos. '
          'Revisa tu conexión e inténtalo de nuevo.';
    } finally {
      _guardando = false;
      notifyListeners();
    }
  }
}
