import 'package:flutter/foundation.dart';

import 'periodicidad_reto.dart';
import 'reto.dart';
import 'tipo_actividad.dart';
import 'vigencia_reto.dart';

/// Campos del formulario de reto.
///
/// El criterio 2 de SCRUM-132 pide señalar *cuáles* requieren corrección, no
/// solo avisar que algo está mal: por eso los errores se devuelven por campo.
enum CampoReto { nombre, descripcion, periodicidad, tipoActividad, meta, xp }

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
    this.tipoActividad,
    this.fin,
    this.meta = '',
    this.xp = '',
  });

  final String nombre;
  final String descripcion;
  final PeriodicidadReto? periodicidad;

  /// Correr, Trote o Caminar. Null hasta que el administrador elige.
  final TipoActividad? tipoActividad;

  /// Hasta cuándo dura, al editar. Null al crear: ahí la vigencia entera la
  /// calcula la periodicidad (SCRUM-142).
  final DateTime? fin;

  final String meta;
  final String xp;

  BorradorReto copyWith({
    String? nombre,
    String? descripcion,
    PeriodicidadReto? periodicidad,
    TipoActividad? tipoActividad,
    DateTime? fin,
    String? meta,
    String? xp,
  }) => BorradorReto(
    nombre: nombre ?? this.nombre,
    descripcion: descripcion ?? this.descripcion,
    periodicidad: periodicidad ?? this.periodicidad,
    tipoActividad: tipoActividad ?? this.tipoActividad,
    fin: fin ?? this.fin,
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
      errores[CampoReto.nombre] = 'Máximo $maxCaracteresNombreReto caracteres.';
    }

    if (descripcion.trim().isEmpty) {
      errores[CampoReto.descripcion] =
          'Explica qué hay que hacer para cumplirlo.';
    }

    if (periodicidad == null) {
      errores[CampoReto.periodicidad] = 'Elige cada cuánto se renueva.';
    }

    // El id, y no solo el nombre: sin sesión el catálogo local viene sin
    // ellos, y la columna de la tabla es una clave foránea.
    if (tipoActividad?.id == null) {
      errores[CampoReto.tipoActividad] = 'Elige el tipo de actividad.';
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

  /// El borrador que corresponde a un reto ya publicado, para editarlo.
  ///
  /// Los números vuelven a texto porque es lo que el formulario maneja; que
  /// `5.0` se vea como `5` lo resuelve [TarjetaReto.textoKm] al pintarlo, no
  /// esta clase.
  factory BorradorReto.de(Reto reto) => BorradorReto(
    nombre: reto.nombre,
    descripcion: reto.descripcion,
    periodicidad: reto.periodicidad,
    tipoActividad: reto.tipoActividad,
    meta: _sinDecimalesSobrantes(reto.metaKm),
    xp: '${reto.xpOtorgada}',
    fin: reto.vigencia.fin,
  );

  /// `5.0` se escribe `5`; `2.5` se queda igual.
  static String _sinDecimalesSobrantes(double valor) =>
      valor == valor.roundToDouble() ? '${valor.round()}' : '$valor';

  /// Los cambios listos para guardar, o null si el borrador tiene errores.
  ///
  /// [original] es el reto tal como está publicado: de él salen la vigencia y
  /// lo que no se edita.
  CambiosReto? aCambios(Reto original) {
    if (!esValido) return null;

    // La fecha de fin solo se mueve hacia adelante. Si el formulario mandara
    // una anterior, `extendidaHasta` devuelve null y se conserva la que había
    // en vez de recortarle el plazo a quien lo esté cumpliendo.
    final nuevaFin = fin;
    final vigencia = nuevaFin == null
        ? original.vigencia
        : original.vigencia.extendidaHasta(nuevaFin) ?? original.vigencia;

    return CambiosReto(
      nombre: nombre.trim(),
      descripcion: descripcion.trim(),
      metaKm: metaKm!,
      xpOtorgada: xpOtorgada!,
      vigencia: vigencia,
    );
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
      tipoActividad: tipoActividad!,
      metaKm: metaKm!,
      xpOtorgada: xpOtorgada!,
      // SCRUM-142: la vigencia no se escribe, se calcula.
      vigencia: periodicidad.vigenciaDesde(ahora),
    );
  }
}

/// Lo que se puede cambiar de un reto ya publicado (SCRUM-133).
///
/// No están ni la periodicidad, ni el tipo de actividad, ni la fecha de
/// inicio: juntos deciden en qué hueco cae el reto y cuándo corre, y moverlos
/// cambiaría de sitio a quien ya lo tiene activo. Para eso se retira el reto
/// y se crea otro.
///
/// Que exista una instancia significa que sus datos ya pasaron las reglas:
/// solo se construye desde [BorradorReto.aCambios].
@immutable
class CambiosReto {
  const CambiosReto({
    required this.nombre,
    required this.descripcion,
    required this.metaKm,
    required this.xpOtorgada,
    required this.vigencia,
  });

  final String nombre;
  final String descripcion;
  final double metaKm;
  final int xpOtorgada;

  /// La vigencia resultante. Solo su fin puede haber cambiado, y solo hacia
  /// adelante: lo garantiza [VigenciaReto.extendidaHasta].
  final VigenciaReto vigencia;

  /// Las columnas que se mandan en el update.
  ///
  /// No va `periodicidad`, ni `tipo_actividad_id`, ni `fecha_inicio`, ni
  /// `estado`: mandar una columna que no cambia es pedirle a la base que la
  /// escriba igual, y el trigger `retos_cambios_permitidos` tendría que
  /// comprobarlas una por una para nada.
  Map<String, dynamic> aSupabase() => {
    'nombre': nombre,
    'descripcion': descripcion,
    'meta_km': metaKm,
    'xp_otorgada': xpOtorgada,
    'fecha_fin': vigencia.finTexto,
  };

  @override
  bool operator ==(Object other) =>
      other is CambiosReto &&
      other.nombre == nombre &&
      other.descripcion == descripcion &&
      other.metaKm == metaKm &&
      other.xpOtorgada == xpOtorgada &&
      other.vigencia == vigencia;

  @override
  int get hashCode =>
      Object.hash(nombre, descripcion, metaKm, xpOtorgada, vigencia);

  @override
  String toString() =>
      'CambiosReto($nombre, $metaKm km, $xpOtorgada XP, hasta '
      '${vigencia.finTexto})';
}

/// Lo que un cambio le hace a quien ya está haciendo el reto (SCRUM-151).
///
/// Solo recoge lo que el corredor nota. Corregir el nombre o la descripción
/// no cambia lo que tiene que hacer ni lo que va a ganar, así que no entra.
extension ConsecuenciasParaElCorredor on CambiosReto {
  /// Las frases que explican qué cambia, en el orden en que importan. Vacía
  /// si nada de lo que el corredor nota se toca.
  List<String> consecuenciasSobre(Reto original) => [
    if (metaKm != original.metaKm)
      'La meta pasa de ${_km(original.metaKm)} a ${_km(metaKm)} km, '
          'con el progreso que ya llevan.',
    if (xpOtorgada != original.xpOtorgada)
      'La XP pasa de ${original.xpOtorgada} a $xpOtorgada.',
    if (vigencia.fin != original.vigencia.fin)
      _plazo(vigencia.dias - original.vigencia.dias),
  ];

  /// `5` en vez de `5.0`; `2.5` se queda igual.
  static String _km(double valor) =>
      valor == valor.roundToDouble() ? '${valor.round()}' : '$valor';

  static String _plazo(int dias) => dias == 1
      ? 'El plazo se alarga un día.'
      : 'El plazo se alarga $dias días.';
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
    required this.tipoActividad,
    required this.metaKm,
    required this.xpOtorgada,
    required this.vigencia,
  });

  final String nombre;
  final String descripcion;
  final PeriodicidadReto periodicidad;
  final TipoActividad tipoActividad;
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
    'tipo_actividad_id': tipoActividad.id,
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
      other.tipoActividad == tipoActividad &&
      other.metaKm == metaKm &&
      other.xpOtorgada == xpOtorgada &&
      other.vigencia == vigencia;

  @override
  int get hashCode => Object.hash(
    nombre,
    descripcion,
    periodicidad,
    tipoActividad,
    metaKm,
    xpOtorgada,
    vigencia,
  );

  @override
  String toString() =>
      'NuevoReto($nombre, ${periodicidad.valorDb}, '
      '${tipoActividad.nombre}, $metaKm km, $xpOtorgada XP)';
}
