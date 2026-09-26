import 'package:flutter/foundation.dart';

import 'nivel.dart';

/// Campos del formulario de nivel.
///
/// El criterio 2 de SCRUM-177 pide indicar *qué* dato corregir, no solo avisar
/// que algo está mal: por eso los errores se devuelven por campo.
enum CampoNivel { nombre, umbral }

/// Cuánto puede medir el nombre de un nivel. Entra en una línea de la tarjeta
/// del listado; más largo, se corta.
const maxCaracteresNombreNivel = 40;

/// Lo que el administrador lleva escrito, todavía sin validar.
///
/// Guarda el umbral como texto, tal cual se teclea, para poder distinguir "no
/// ha escrito nada" de "escribió algo que no es un número": convertirlo antes
/// de validar perdería esa diferencia.
@immutable
class BorradorNivel {
  const BorradorNivel({this.nombre = '', this.umbral = ''});

  final String nombre;
  final String umbral;

  BorradorNivel copyWith({String? nombre, String? umbral}) => BorradorNivel(
    nombre: nombre ?? this.nombre,
    umbral: umbral ?? this.umbral,
  );

  /// El umbral como entero, o null si lo escrito no lo es.
  ///
  /// No admite decimales: la experiencia se acumula de a puntos enteros, igual
  /// que la XP que otorgan los retos.
  int? get umbralExperiencia {
    final limpio = umbral.trim();
    return limpio.isEmpty ? null : int.tryParse(limpio);
  }

  /// Qué le falta o qué está mal, por campo, comparado con los [existentes].
  /// Vacío si se puede guardar.
  ///
  /// Las mismas reglas están en las restricciones de la tabla `niveles`
  /// (`0007_niveles.sql`), que son la última palabra. Aquí existen para que el
  /// administrador sepa qué corregir antes de que la base lo rechace, y sobre
  /// todo para poder decirle **con cuál nivel** choca: eso Postgres no lo
  /// cuenta, solo dice que se violó una restricción.
  Map<CampoNivel, String> erroresFrenteA(List<Nivel> existentes) {
    final errores = <CampoNivel, String>{};
    final nombre = this.nombre.trim();

    // Obligatorio es tener contenido, no solo estar presente: una cadena de
    // espacios no es un nombre.
    if (nombre.isEmpty) {
      errores[CampoNivel.nombre] = 'Ponle un nombre al nivel.';
    } else if (nombre.length > maxCaracteresNombreNivel) {
      errores[CampoNivel.nombre] =
          'Máximo $maxCaracteresNombreNivel '
          'caracteres.';
    } else {
      final repetido = _conMismoNombre(existentes, nombre);
      if (repetido != null) {
        errores[CampoNivel.nombre] =
            'Ya existe un nivel llamado '
            '"${repetido.nombre}".';
      }
    }

    final umbral = umbralExperiencia;
    if (this.umbral.trim().isEmpty) {
      errores[CampoNivel.umbral] =
          'Indica la experiencia necesaria para '
          'alcanzarlo.';
    } else if (umbral == null) {
      errores[CampoNivel.umbral] = 'Usa solo números enteros.';
    } else if (umbral <= 0) {
      errores[CampoNivel.umbral] = 'El umbral debe ser mayor que cero.';
    } else {
      final ocupado = _conMismoUmbral(existentes, umbral);
      if (ocupado != null) {
        errores[CampoNivel.umbral] =
            'Ese umbral ya lo usa "${ocupado.nombre}". '
            'Cada nivel empieza en uno distinto.';
      }
    }

    return errores;
  }

  bool esValidoFrenteA(List<Nivel> existentes) =>
      erroresFrenteA(existentes).isEmpty;

  /// El nivel listo para guardar, o null si el borrador todavía tiene errores.
  ///
  /// Devolver null y no lanzar es lo que **impide el registro**: quien quiera
  /// crear un nivel tiene que pasar por aquí, y sin datos válidos no obtiene
  /// nada que registrar.
  NuevoNivel? aNuevoNivel(List<Nivel> existentes) {
    if (!esValidoFrenteA(existentes)) return null;
    return NuevoNivel(
      nombre: nombre.trim(),
      umbralExperiencia: umbralExperiencia!,
    );
  }

  /// El nivel que ya se llama así, o null.
  ///
  /// Compara sin mayúsculas ni espacios de sobra, igual que el índice único de
  /// la tabla: "Bronce", "bronce" y " Bronce " son el mismo nivel para quien
  /// lo lee.
  static Nivel? _conMismoNombre(List<Nivel> existentes, String nombre) {
    final buscado = nombre.toLowerCase();
    for (final nivel in existentes) {
      if (nivel.nombre.trim().toLowerCase() == buscado) return nivel;
    }
    return null;
  }

  /// El nivel que ya empieza en ese umbral, o null.
  ///
  /// Con un umbral por nivel, que dos se solapen es que empiecen en la misma
  /// experiencia: quedarían ocupando el mismo tramo de la progresión.
  static Nivel? _conMismoUmbral(List<Nivel> existentes, int umbral) {
    for (final nivel in existentes) {
      if (nivel.umbralExperiencia == umbral) return nivel;
    }
    return null;
  }
}

/// Un nivel validado, listo para registrar.
///
/// Que exista una instancia significa que sus datos ya pasaron las reglas:
/// solo se construye desde [BorradorNivel.aNuevoNivel].
@immutable
class NuevoNivel {
  const NuevoNivel({required this.nombre, required this.umbralExperiencia});

  final String nombre;
  final int umbralExperiencia;

  /// Las columnas de `niveles` tal como las espera Supabase.
  ///
  /// `creado_por` no va aquí: lo pone el repositorio con la cuenta que tiene
  /// la sesión abierta, no el formulario.
  Map<String, dynamic> aSupabase() => {
    'nombre': nombre,
    'umbral_experiencia': umbralExperiencia,
  };

  @override
  bool operator ==(Object other) =>
      other is NuevoNivel &&
      other.nombre == nombre &&
      other.umbralExperiencia == umbralExperiencia;

  @override
  int get hashCode => Object.hash(nombre, umbralExperiencia);

  @override
  String toString() => 'NuevoNivel($nombre, $umbralExperiencia XP)';
}
