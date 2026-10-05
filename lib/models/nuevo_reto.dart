import 'package:flutter/foundation.dart';

import 'periodicidad_reto.dart';
import 'vigencia_reto.dart';

/// Campos del formulario de reto.
///
/// El criterio 2 de SCRUM-132 pide señalar *cuáles* requieren corrección, no
/// solo avisar que algo está mal: por eso los errores se devuelven por campo.
enum CampoReto { nombre, descripcion, periodicidad, meta, xp }

/// Cuánto puede medir el nombre de un reto. Entra en una línea de la tarjeta
/// del catálogo; más largo, se corta.
const maxCaracteresNombreReto = 60;

/// Lo que el administrador lleva escrito, todavía sin validar.
///
/// Guarda los números como texto, tal cual se teclean, para poder distinguir
/// "no ha escrito nada" de "escribió algo que no es un número": convertirlos
/// antes de validar perdería esa diferencia.
@immutable
class BorradorReto {
  const BorradorReto({
    this.nombre = '',
    this.descripcion = '',
    this.periodicidad,
    this.meta = '',
    this.xp = '',
  });

  final String nombre;
  final String descripcion;
  final PeriodicidadReto? periodicidad;
  final String meta;
  final String xp;

  BorradorReto copyWith({
    String? nombre,
    String? descripcion,
    PeriodicidadReto? periodicidad,
    String? meta,
    String? xp,
  }) => BorradorReto(
    nombre: nombre ?? this.nombre,
    descripcion: descripcion ?? this.descripcion,
    periodicidad: periodicidad ?? this.periodicidad,
    meta: meta ?? this.meta,
    xp: xp ?? this.xp,
  );

  /// Qué le falta o qué está mal, por campo. Vacío si se puede guardar.
  ///
  /// Las mismas reglas están en las restricciones de la tabla `retos`
  /// (`0006_retos.sql`), que son la última palabra. Aquí existen para que el
  /// administrador sepa qué corregir antes de que la base lo rechace.
  Map<CampoReto, String> get errores {
    final errores = <CampoReto, String>{};

    // Obligatorio es tener contenido, no solo estar presente: una cadena de
    // espacios no es un nombre.
    if (nombre.trim().isEmpty) {
      errores[CampoReto.nombre] = 'Ponle un nombre al reto.';
    } else if (nombre.trim().length > maxCaracteresNombreReto) {
      errores[CampoReto.nombre] =
          'Máximo $maxCaracteresNombreReto caracteres.';
    }

    if (descripcion.trim().isEmpty) {
      errores[CampoReto.descripcion] =
          'Explica qué hay que hacer para cumplirlo.';
    }

    if (periodicidad == null) {
      errores[CampoReto.periodicidad] = 'Elige cada cuánto se renueva.';
    }

    final meta = metaKm;
    if (this.meta.trim().isEmpty) {
      errores[CampoReto.meta] = 'Indica la meta en kilómetros.';
    } else if (meta == null) {
      errores[CampoReto.meta] = 'Ingresa un número válido.';
    } else if (meta <= 0) {
      errores[CampoReto.meta] = 'La meta debe ser mayor que cero.';
    }

    final xp = xpOtorgada;
    if (this.xp.trim().isEmpty) {
      errores[CampoReto.xp] = 'Indica cuánta XP otorga.';
    } else if (xp == null) {
      errores[CampoReto.xp] = 'Usa solo números enteros.';
    } else if (xp <= 0) {
      errores[CampoReto.xp] = 'La XP debe ser mayor que cero.';
    }

    return errores;
  }

  bool get esValido => errores.isEmpty;

  /// La meta como número, o null si lo escrito no lo es.
  ///
  /// Admite coma o punto: el teclado del usuario puede ofrecer cualquiera de
  /// los dos, igual que en los objetivos del perfil.
  double? get metaKm {
    final limpio = meta.trim().replaceAll(',', '.');
    return limpio.isEmpty ? null : double.tryParse(limpio);
  }

  /// La XP como entero, o null. No admite decimales: la XP se otorga entera.
  int? get xpOtorgada {
    final limpio = xp.trim();
    return limpio.isEmpty ? null : int.tryParse(limpio);
  }

  /// El reto listo para guardar, o null si el borrador todavía tiene errores.
  ///
  /// Devolver null y no lanzar es lo que **impide el guardado** que pide
  /// SCRUM-141: quien quiera registrar un reto tiene que pasar por aquí, y sin
  /// datos válidos no obtiene nada que registrar.
  NuevoReto? aNuevoReto({required DateTime ahora}) {
    if (!esValido) return null;
    final periodicidad = this.periodicidad!;
    return NuevoReto(
      nombre: nombre.trim(),
      descripcion: descripcion.trim(),
      periodicidad: periodicidad,
      metaKm: metaKm!,
      xpOtorgada: xpOtorgada!,
      // SCRUM-142: la vigencia no se escribe, se calcula.
      vigencia: periodicidad.vigenciaDesde(ahora),
    );
  }
}

/// Un reto validado, listo para registrar.
///
/// Que exista una instancia significa que sus datos ya pasaron las reglas:
/// solo se construye desde [BorradorReto.aNuevoReto].
@immutable
class NuevoReto {
  const NuevoReto({
    required this.nombre,
    required this.descripcion,
    required this.periodicidad,
    required this.metaKm,
    required this.xpOtorgada,
    required this.vigencia,
  });

  final String nombre;
  final String descripcion;
  final PeriodicidadReto periodicidad;
  final double metaKm;
  final int xpOtorgada;
  final VigenciaReto vigencia;

  /// Las columnas de `retos` tal como las espera Supabase.
  ///
  /// `estado` no va: lo pone el default `'activo'` de la tabla (SCRUM-145).
  /// Mandarlo desde el cliente abriría la puerta a crear un reto ya retirado.
  Map<String, dynamic> aSupabase() => {
    'nombre': nombre,
    'descripcion': descripcion,
    'periodicidad': periodicidad.valorDb,
    'meta_km': metaKm,
    'xp_otorgada': xpOtorgada,
    'fecha_inicio': vigencia.inicioTexto,
    'fecha_fin': vigencia.finTexto,
  };

  @override
  bool operator ==(Object other) =>
      other is NuevoReto &&
      other.nombre == nombre &&
      other.descripcion == descripcion &&
      other.periodicidad == periodicidad &&
      other.metaKm == metaKm &&
      other.xpOtorgada == xpOtorgada &&
      other.vigencia == vigencia;

  @override
  int get hashCode => Object.hash(
    nombre,
    descripcion,
    periodicidad,
    metaKm,
    xpOtorgada,
    vigencia,
  );

  @override
  String toString() =>
      'NuevoReto($nombre, ${periodicidad.valorDb}, $metaKm km, $xpOtorgada XP)';
}
