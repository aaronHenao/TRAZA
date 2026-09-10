import 'package:flutter/foundation.dart';

import '../domain/tipo_objetivo.dart';
import '../domain/validacion_objetivo.dart';

/// Estado de la sección "Mis Objetivos" del perfil.
///
/// Es inmutable: cada cambio produce una instancia nueva con [copyWith]. Los
/// datos derivados (errores, validez, qué se va a guardar) se calculan aquí
/// para que la interfaz no tenga que repetir la lógica.
@immutable
class PerfilState {
  const PerfilState({
    required this.seleccionados,
    required this.textos,
    this.guardando = false,
  });

  factory PerfilState.inicial() => PerfilState(
    seleccionados: const <TipoObjetivo>{},
    textos: {
      for (final tipo in TipoObjetivo.values)
        tipo: formatearValorObjetivo(tipo.valorPorDefecto),
    },
  );

  /// Objetivos que el usuario tiene marcados.
  final Set<TipoObjetivo> seleccionados;

  /// Texto crudo de cada campo. Se conserva aunque el objetivo se desmarque,
  /// para que al volver a marcarlo reaparezca lo que el usuario había escrito.
  final Map<TipoObjetivo, String> textos;

  final bool guardando;

  PerfilState copyWith({
    Set<TipoObjetivo>? seleccionados,
    Map<TipoObjetivo, String>? textos,
    bool? guardando,
  }) => PerfilState(
    seleccionados: seleccionados ?? this.seleccionados,
    textos: textos ?? this.textos,
    guardando: guardando ?? this.guardando,
  );

  bool get sinObjetivos => seleccionados.isEmpty;

  bool estaSeleccionado(TipoObjetivo tipo) => seleccionados.contains(tipo);

  String textoDe(TipoObjetivo tipo) => textos[tipo]!;

  /// Mensaje de error del valor actual, o null si es válido.
  String? errorDe(TipoObjetivo tipo) =>
      validarValorObjetivo(tipo, textoDe(tipo));

  /// Valor listo para guardar, o null si el texto actual no es válido.
  num? valorDe(TipoObjetivo tipo) => errorDe(tipo) == null
      ? interpretarValorObjetivo(tipo, textoDe(tipo))
      : null;

  /// True si algún objetivo marcado tiene un valor que no se puede guardar.
  bool get hayValoresInvalidos =>
      seleccionados.any((tipo) => errorDe(tipo) != null);

  /// Objetivos marcados con su valor, tal como se van a persistir.
  Map<TipoObjetivo, num> get objetivosAGuardar => {
    for (final tipo in seleccionados) tipo: ?valorDe(tipo),
  };

  bool get puedeGuardar => !sinObjetivos && !hayValoresInvalidos && !guardando;
}
