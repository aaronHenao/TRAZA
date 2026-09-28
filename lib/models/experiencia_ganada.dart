import 'package:flutter/foundation.dart';

import 'regla_experiencia.dart';

/// Un reto que se completó al finalizar un entrenamiento (SCRUM-205).
@immutable
class RetoCompletado {
  const RetoCompletado({required this.nombre, required this.xp});

  final String nombre;
  final int xp;

  @override
  bool operator ==(Object other) =>
      other is RetoCompletado && other.nombre == nombre && other.xp == xp;

  @override
  int get hashCode => Object.hash(nombre, xp);

  @override
  String toString() => 'RetoCompletado($nombre, $xp XP)';
}

/// La XP que dejó un entrenamiento finalizado (SCRUM-203, SCRUM-205).
///
/// La calcula el trigger de `0009_experiencia.sql` al finalizar; esto es lo
/// que quedó registrado en `experiencia_ganada`.
@immutable
class ExperienciaDeEntrenamiento {
  const ExperienciaDeEntrenamiento({
    required this.xpActividad,
    required this.ajuste,
    this.retos = const [],
  });

  /// XP por la actividad en sí: la distancia, con el mínimo, la velocidad y
  /// el tope del día aplicados.
  final int xpActividad;

  /// Por qué la actividad dio menos de lo que daría su distancia completa.
  final AjusteExperiencia ajuste;

  final List<RetoCompletado> retos;

  int get total => retos.fold(xpActividad, (suma, reto) => suma + reto.xp);

  /// Nombre de respaldo para un reto que el usuario ya no puede ver (el
  /// administrador lo retiró después).
  static const nombreRetoOculto = 'Reto';

  static const _ajustes = {
    'ninguno': AjusteExperiencia.ninguno,
    'sin_datos': AjusteExperiencia.sinDatos,
    'velocidad_imposible': AjusteExperiencia.velocidadImposible,
    'menos_del_minimo': AjusteExperiencia.menosDelMinimo,
    'tope_diario': AjusteExperiencia.topeDiario,
  };

  /// Lee las filas de `experiencia_ganada` de un entrenamiento, con el nombre
  /// del reto embebido (`retos_usuario(retos(nombre))`).
  ///
  /// Devuelve null si no hay fila de actividad: el entrenamiento no se
  /// procesó (se finalizó antes de la migración, o la XP falló y el trigger
  /// la dejó pasar para no perder el entrenamiento).
  ///
  /// Lanza [FormatException] si una fila no encaja con el esquema.
  static ExperienciaDeEntrenamiento? desdeFilas(
    List<Map<String, dynamic>> filas,
  ) {
    int? xpActividad;
    AjusteExperiencia? ajuste;
    final retos = <RetoCompletado>[];

    for (final fila in filas) {
      final cantidad = fila['cantidad'];
      if (cantidad is! num) {
        throw FormatException('Fila de experiencia sin cantidad', fila);
      }

      switch (fila['origen']) {
        case 'actividad':
          ajuste = _ajustes[fila['ajuste']];
          if (ajuste == null) {
            throw FormatException('Ajuste de experiencia desconocido', fila);
          }
          xpActividad = cantidad.toInt();
        case 'reto':
          retos.add(
            RetoCompletado(
              nombre: _nombreDelReto(fila) ?? nombreRetoOculto,
              xp: cantidad.toInt(),
            ),
          );
        default:
          throw FormatException('Origen de experiencia desconocido', fila);
      }
    }

    if (xpActividad == null || ajuste == null) return null;
    return ExperienciaDeEntrenamiento(
      xpActividad: xpActividad,
      ajuste: ajuste,
      retos: List.unmodifiable(retos),
    );
  }

  static String? _nombreDelReto(Map<String, dynamic> fila) {
    final retoUsuario = fila['retos_usuario'];
    if (retoUsuario is! Map) return null;
    final reto = retoUsuario['retos'];
    if (reto is! Map) return null;
    final nombre = reto['nombre'];
    return nombre is String ? nombre : null;
  }

  @override
  bool operator ==(Object other) =>
      other is ExperienciaDeEntrenamiento &&
      other.xpActividad == xpActividad &&
      other.ajuste == ajuste &&
      listEquals(other.retos, retos);

  @override
  int get hashCode => Object.hash(xpActividad, ajuste, Object.hashAll(retos));

  @override
  String toString() =>
      'ExperienciaDeEntrenamiento($xpActividad XP, ${ajuste.name}, $retos)';
}
