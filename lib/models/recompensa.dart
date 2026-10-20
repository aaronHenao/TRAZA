import 'package:flutter/foundation.dart';

/// Campos del formulario de recompensa.
///
/// El criterio 2 de SCRUM-374 pide señalar los campos por corregir, no solo
/// avisar que algo está mal: por eso los errores se devuelven por campo.
enum CampoRecompensa { nombre, descripcion, puntos }

/// Lo que admiten los `check` de `recompensas` (`0037_recompensas.sql`).
const maxCaracteresNombreRecompensa = 60;
const maxCaracteresDescripcionRecompensa = 280;

/// Tope de puntos de una recompensa. Muy por encima de cualquier recompensa
/// real, y muy por debajo de lo que cabe en la columna `integer`: sin él, un
/// número enorme pasaría la validación y fallaría al guardar sin decir qué
/// campo corregir.
const maxPuntosRecompensa = 1000000;

/// Una recompensa del catálogo, tal como vive en `recompensas` (SCRUM-374).
@immutable
class Recompensa {
  const Recompensa({
    required this.id,
    required this.nombre,
    required this.descripcion,
    required this.puntosRequeridos,
    required this.disponible,
    required this.fechaCreacion,
  });

  final String id;
  final String nombre;
  final String descripcion;

  /// Cuántos puntos cuesta obtenerla (criterio 3).
  final int puntosRequeridos;

  /// Si los corredores la ven en su catálogo.
  final bool disponible;

  final DateTime fechaCreacion;

  factory Recompensa.desdeSupabase(Map<String, dynamic> fila) {
    final id = fila['id'];
    final nombre = fila['nombre'];
    final descripcion = fila['descripcion'];
    final puntos = fila['puntos_requeridos'];
    final disponible = fila['disponible'];
    final fecha = fila['fecha_creacion'];
    final fechaCreacion = fecha is String ? DateTime.tryParse(fecha) : null;

    if (id is! String ||
        nombre is! String ||
        descripcion is! String ||
        puntos is! int ||
        disponible is! bool ||
        fechaCreacion == null) {
      throw FormatException(
        'Fila de recompensas incompleta o inesperada',
        fila,
      );
    }

    return Recompensa(
      id: id,
      nombre: nombre,
      descripcion: descripcion,
      puntosRequeridos: puntos,
      disponible: disponible,
      fechaCreacion: fechaCreacion.toLocal(),
    );
  }

  @override
  bool operator ==(Object other) => other is Recompensa && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Recompensa($nombre, $puntosRequeridos)';
}

/// Lo que el administrador lleva escrito, todavía sin validar.
///
/// Los puntos se guardan como texto, tal cual se teclean, para distinguir "no
/// ha escrito nada" de "escribió algo que no es un número".
@immutable
class BorradorRecompensa {
  const BorradorRecompensa({
    this.nombre = '',
    this.descripcion = '',
    this.puntos = '',
    this.disponible = true,
  });

  final String nombre;
  final String descripcion;
  final String puntos;

  /// Encendida por defecto: lo normal es crearla para ofrecerla ya.
  final bool disponible;

  BorradorRecompensa copyWith({
    String? nombre,
    String? descripcion,
    String? puntos,
    bool? disponible,
  }) => BorradorRecompensa(
    nombre: nombre ?? this.nombre,
    descripcion: descripcion ?? this.descripcion,
    puntos: puntos ?? this.puntos,
    disponible: disponible ?? this.disponible,
  );

  /// Los puntos escritos, o null si no son un entero.
  int? get puntosRequeridos => int.tryParse(puntos.trim());

  /// Qué le falta o qué está mal, por campo. Vacío si se puede guardar.
  ///
  /// Las mismas reglas están en los `check` de `recompensas`, que son la
  /// última palabra. Aquí existen para que el administrador sepa qué corregir
  /// antes de que la base lo rechace.
  Map<CampoRecompensa, String> get errores {
    final errores = <CampoRecompensa, String>{};

    final nombre = this.nombre.trim();
    if (nombre.isEmpty) {
      errores[CampoRecompensa.nombre] = 'Ponle un nombre a la recompensa.';
    } else if (nombre.length > maxCaracteresNombreRecompensa) {
      errores[CampoRecompensa.nombre] =
          'Máximo $maxCaracteresNombreRecompensa caracteres.';
    }

    final descripcion = this.descripcion.trim();
    if (descripcion.isEmpty) {
      errores[CampoRecompensa.descripcion] = 'Describe en qué consiste.';
    } else if (descripcion.length > maxCaracteresDescripcionRecompensa) {
      errores[CampoRecompensa.descripcion] =
          'Máximo $maxCaracteresDescripcionRecompensa caracteres.';
    }

    final puntos = puntosRequeridos;
    if (this.puntos.trim().isEmpty) {
      errores[CampoRecompensa.puntos] = 'Indica cuántos puntos cuesta.';
    } else if (puntos == null) {
      errores[CampoRecompensa.puntos] = 'Usa solo números enteros.';
    } else if (puntos <= 0) {
      errores[CampoRecompensa.puntos] =
          'Los puntos deben ser mayores que cero.';
    } else if (puntos > maxPuntosRecompensa) {
      errores[CampoRecompensa.puntos] = 'Máximo $maxPuntosRecompensa puntos.';
    }

    return errores;
  }

  bool get esValido => errores.isEmpty;

  /// La recompensa lista para registrar, o null si no pasa las reglas.
  NuevaRecompensa? aNuevaRecompensa() {
    if (!esValido) return null;
    return NuevaRecompensa(
      nombre: nombre.trim(),
      descripcion: descripcion.trim(),
      puntosRequeridos: puntosRequeridos!,
      disponible: disponible,
    );
  }
}

/// Una recompensa validada, lista para registrar.
///
/// Que exista una instancia significa que sus datos ya pasaron las reglas:
/// solo se construye desde [BorradorRecompensa.aNuevaRecompensa].
@immutable
class NuevaRecompensa {
  const NuevaRecompensa({
    required this.nombre,
    required this.descripcion,
    required this.puntosRequeridos,
    required this.disponible,
  });

  final String nombre;
  final String descripcion;
  final int puntosRequeridos;
  final bool disponible;

  /// Las columnas de `recompensas` tal como las espera Supabase. Sin id ni
  /// fecha: los pone la base.
  Map<String, dynamic> aSupabase() => {
    'nombre': nombre,
    'descripcion': descripcion,
    'puntos_requeridos': puntosRequeridos,
    'disponible': disponible,
  };

  @override
  bool operator ==(Object other) =>
      other is NuevaRecompensa &&
      other.nombre == nombre &&
      other.descripcion == descripcion &&
      other.puntosRequeridos == puntosRequeridos &&
      other.disponible == disponible;

  @override
  int get hashCode =>
      Object.hash(nombre, descripcion, puntosRequeridos, disponible);
}
