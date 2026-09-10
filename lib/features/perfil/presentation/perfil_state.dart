import 'package:flutter/foundation.dart';

import '../domain/tipo_objetivo.dart';
import '../domain/validacion_objetivo.dart';

/// Estado de la sección "Mis Objetivos" del perfil.
///
/// Es inmutable: cada cambio produce una instancia nueva con [copyWith]. Los
/// datos derivados (errores, validez, qué se va a guardar) se calculan aquí
/// para que la interfaz no tenga que repetir la lógica.
/// Cómo va la lectura de los objetivos que el usuario ya tenía guardados.
enum EstadoCarga { cargando, listo, error }

@immutable
class PerfilState {
  const PerfilState({
    required this.seleccionados,
    required this.textos,
    this.carga = EstadoCarga.cargando,
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

  final EstadoCarga carga;

  final bool guardando;

  PerfilState copyWith({
    Set<TipoObjetivo>? seleccionados,
    Map<TipoObjetivo, String>? textos,
    EstadoCarga? carga,
    bool? guardando,
  }) => PerfilState(
    seleccionados: seleccionados ?? this.seleccionados,
    textos: textos ?? this.textos,
    carga: carga ?? this.carga,
    guardando: guardando ?? this.guardando,
  );

  /// Precarga lo que el usuario ya tenía guardado: marca esos objetivos y pone
  /// sus valores. Los que no estaban guardados conservan el valor por defecto.
  PerfilState conObjetivosGuardados(Map<TipoObjetivo, num> guardados) =>
      copyWith(
        carga: EstadoCarga.listo,
        seleccionados: guardados.keys.toSet(),
        textos: {
          ...textos,
          for (final MapEntry(key: tipo, value: valor) in guardados.entries)
            tipo: formatearValorObjetivo(valor),
        },
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

  /// No se guarda si la carga falló: como el guardado reemplaza el conjunto
  /// completo, hacerlo sin saber qué había borraría los objetivos existentes.
  bool get puedeGuardar =>
      carga == EstadoCarga.listo &&
      !sinObjetivos &&
      !hayValoresInvalidos &&
      !guardando;
}
