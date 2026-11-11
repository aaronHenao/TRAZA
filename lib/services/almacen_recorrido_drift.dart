import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../models/punto_pendiente.dart';
import '../models/recorrido_local.dart';
// Import circular a propósito: `almacen_recorrido.dart` tiene la interfaz y
// el provider que crea esta clase. Así los servicios y las pruebas siguen
// importando un solo archivo, como antes de Drift.
import 'almacen_recorrido.dart';
import 'base_local.dart';

/// Los recorridos que esperan subir a Supabase, en SQLite con Drift (Drift,
/// Desarrollo Móvil). Reemplaza a los archivos JSONL de SCRUM-292 con la
/// misma interfaz, así que el tracking no cambia.
///
/// Lo que añade:
///   · cada recorrido sabe de qué cuenta es, y solo se reenvía lo de la
///     cuenta con sesión: lo de otra se queda hasta que vuelva;
///   · lleva su estado de sincronización (`pendiente_sync`, `ultimo_error`,
///     `rechazado`, `actualizado_en`) para la pantalla que lo muestra;
///   · la primera vez que se usa, trae lo que quedara en los archivos.
class AlmacenRecorridoDrift implements AlmacenRecorrido {
  AlmacenRecorridoDrift(
    this._base, {
    required String? Function() usuarioActual,
    AlmacenRecorrido? archivosViejos,
    DateTime Function()? reloj,
  }) : _usuarioActual = usuarioActual,
       _archivosViejos = archivosViejos,
       _reloj = reloj ?? DateTime.now;

  final BaseLocal _base;
  final String? Function() _usuarioActual;
  final AlmacenRecorrido? _archivosViejos;
  final DateTime Function() _reloj;

  /// De dónde trae lo de antes de Drift. Para comprobar que la app lo pasa.
  @visibleForTesting
  AlmacenRecorrido? get archivosViejos => _archivosViejos;

  Future<void>? _importacion;

  /// Cada operación espera a que lo viejo ya esté aquí.
  Future<void> _listo() => _importacion ??= _importar();

  /// Trae los recorridos de los archivos JSONL, sin dueño (no lo guardaban),
  /// y solo después borra cada archivo. Si algo falla, el archivo se queda y
  /// se vuelve a intentar en el próximo arranque.
  Future<void> _importar() async {
    final viejos = _archivosViejos;
    if (viejos == null) return;

    final List<String> ids;
    try {
      ids = await viejos.conPendientes();
    } catch (error) {
      // Solo el tipo: el error de SQLite puede traer la fila, con su
      // ubicación (auditoría de seguridad).
      debugPrint(
        'No se pudieron mirar los recorridos en archivos: '
        '${error.runtimeType}',
      );
      return;
    }

    for (final id in ids) {
      try {
        final puntos = await viejos.pendientes(id);
        // Sin dueño: los archivos no lo guardaban.
        if (puntos.isNotEmpty) await _guardar(id, puntos);
      } catch (error) {
        debugPrint(
          'No se pudo importar el recorrido en archivo: ${error.runtimeType}',
        );
        continue;
      }
      try {
        await viejos.olvidar(id);
      } catch (error) {
        // Lo importado ya está aquí; el archivo se reintentará borrar
        // la próxima vez, y volver a importarlo no duplica nada.
        debugPrint(
          'No se pudo borrar el recorrido en archivo: ${error.runtimeType}',
        );
      }
    }
  }

  /// Crea el recorrido (con [usuarioId] como dueño) o lo actualiza, y guarda
  /// sus puntos. Un recorrido que ya existe conserva su dueño.
  Future<void> _guardar(
    String id,
    List<PuntoPendiente> puntos, {
    String? usuarioId,
  }) async {
    final ahora = _reloj();
    await _base.transaction(() async {
      await _base
          .into(_base.recorridosLocales)
          .insert(
            RecorridosLocalesCompanion.insert(
              entrenamientoId: id,
              usuarioId: Value(usuarioId),
              actualizadoEn: ahora,
            ),
            onConflict: DoUpdate(
              (_) => RecorridosLocalesCompanion(
                actualizadoEn: Value(ahora),
                pendienteSync: const Value(true),
              ),
            ),
          );
      await _guardarPuntos(id, puntos);
    });
  }

  Future<void> _guardarPuntos(String id, List<PuntoPendiente> puntos) async {
    await _base.batch((lote) {
      lote.insertAllOnConflictUpdate(_base.puntosLocales, [
        for (final punto in puntos)
          PuntosLocalesCompanion.insert(
            entrenamientoId: id,
            orden: punto.orden,
            tramo: punto.tramo,
            latitud: punto.latitud,
            longitud: punto.longitud,
            capturadoEn: punto.capturadoEn,
          ),
      ]);
    });
  }

  @override
  Future<void> anadir(String entrenamientoId, PuntoPendiente punto) async {
    await _listo();
    // El dueño se fija al crear el recorrido: es quien está corriendo.
    await _guardar(entrenamientoId, [punto], usuarioId: _usuarioActual());
  }

  @override
  Future<List<PuntoPendiente>> pendientes(String entrenamientoId) async {
    await _listo();
    final filas =
        await (_base.select(_base.puntosLocales)
              ..where((p) => p.entrenamientoId.equals(entrenamientoId))
              ..orderBy([(p) => OrderingTerm.asc(p.orden)]))
            .get();
    return [
      for (final fila in filas)
        PuntoPendiente(
          latitud: fila.latitud,
          longitud: fila.longitud,
          capturadoEn: fila.capturadoEn.toLocal(),
          orden: fila.orden,
          tramo: fila.tramo,
        ),
    ];
  }

  @override
  Future<void> marcarEnviados(String entrenamientoId, int hastaOrden) async {
    await _listo();
    await _base.transaction(() async {
      await (_base.delete(_base.puntosLocales)..where(
            (p) =>
                p.entrenamientoId.equals(entrenamientoId) &
                p.orden.isSmallerOrEqualValue(hastaOrden),
          ))
          .go();
      final quedan = await _cuantosPuntos(entrenamientoId);
      // Un envío que salió bien deja atrás el error anterior.
      await (_base.update(
        _base.recorridosLocales,
      )..where((r) => r.entrenamientoId.equals(entrenamientoId))).write(
        RecorridosLocalesCompanion(
          actualizadoEn: Value(_reloj()),
          pendienteSync: Value(quedan > 0),
          ultimoError: const Value(null),
        ),
      );
    });
  }

  @override
  Future<void> olvidar(String entrenamientoId) async {
    await _listo();
    // Sus puntos se van con él: `on delete cascade` (base_local.dart).
    await (_base.delete(
      _base.recorridosLocales,
    )..where((r) => r.entrenamientoId.equals(entrenamientoId))).go();
  }

  @override
  Future<List<String>> conPendientes() async {
    await _listo();
    final usuario = _usuarioActual();
    // Sin sesión no se sube nada: la base no sabría de quién es.
    if (usuario == null) return const [];

    // También los enviados del todo que no se olvidaron (la app se cerró
    // antes del olvido): el reenvío los limpia y verifica su ruta, como
    // hacía con los archivos.
    final filas =
        await (_base.select(_base.recorridosLocales)
              ..where(
                (r) =>
                    r.rechazado.equals(false) &
                    (r.usuarioId.equals(usuario) | r.usuarioId.isNull()),
              )
              ..orderBy([(r) => OrderingTerm.asc(r.entrenamientoId)]))
            .get();
    return [for (final fila in filas) fila.entrenamientoId];
  }

  @override
  Future<void> registrarError(
    String entrenamientoId,
    String motivo, {
    bool rechazado = false,
  }) async {
    await _listo();
    await _base.transaction(() async {
      await (_base.update(
        _base.recorridosLocales,
      )..where((r) => r.entrenamientoId.equals(entrenamientoId))).write(
        RecorridosLocalesCompanion(
          actualizadoEn: Value(_reloj()),
          ultimoError: Value(motivo),
          rechazado: const Value(false),
        ),
      );
      // Un recorrido sin dueño rechazado con la sesión de una cuenta puede
      // ser de otra: no se da por perdido, su dueño lo podrá subir.
      if (rechazado) {
        await (_base.update(_base.recorridosLocales)..where(
              (r) =>
                  r.entrenamientoId.equals(entrenamientoId) &
                  r.usuarioId.isNotNull(),
            ))
            .write(const RecorridosLocalesCompanion(rechazado: Value(true)));
      }
    });
  }

  @override
  Stream<List<RecorridoLocal>> recorridosDeLaCuenta() async* {
    await _listo();
    final usuario = _usuarioActual();
    if (usuario == null) {
      yield const [];
      return;
    }

    final consulta = _base.customSelect(
      'SELECT r.*, '
      '(SELECT COUNT(*) FROM puntos_locales p '
      'WHERE p.entrenamiento_id = r.entrenamiento_id) AS puntos '
      'FROM recorridos_locales r '
      // Los sin dueño no: podrían ser de otra cuenta del mismo teléfono.
      'WHERE r.usuario_id = ?',
      variables: [Variable.withString(usuario)],
      readsFrom: {_base.recorridosLocales, _base.puntosLocales},
    );

    yield* consulta.watch().map((filas) {
      final recorridos = [
        for (final fila in filas)
          RecorridoLocal(
            entrenamientoId: fila.read<String>('entrenamiento_id'),
            usuarioId: fila.readNullable<String>('usuario_id'),
            actualizadoEn: fila.read<DateTime>('actualizado_en').toLocal(),
            pendienteSync: fila.read<bool>('pendiente_sync'),
            ultimoError: fila.readNullable<String>('ultimo_error'),
            rechazado: fila.read<bool>('rechazado'),
            puntosSinEnviar: fila.read<int>('puntos'),
          ),
      ]..sort((a, b) => b.actualizadoEn.compareTo(a.actualizadoEn));
      return recorridos;
    });
  }

  Future<int> _cuantosPuntos(String entrenamientoId) async {
    final contar = _base.puntosLocales.orden.count();
    final consulta = _base.selectOnly(_base.puntosLocales)
      ..addColumns([contar])
      ..where(_base.puntosLocales.entrenamientoId.equals(entrenamientoId));
    return (await consulta.getSingle()).read(contar) ?? 0;
  }
}
