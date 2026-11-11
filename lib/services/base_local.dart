import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'base_local.g.dart';

/// Un recorrido guardado en el teléfono hasta que Supabase lo tenga entero
/// (Drift, Desarrollo Móvil).
@DataClassName('FilaRecorrido')
class RecorridosLocales extends Table {
  /// El id del entrenamiento en Supabase: estable, el mismo aquí y allá.
  TextColumn get entrenamientoId => text()();

  /// La cuenta dueña. Null en lo importado de los archivos de antes.
  TextColumn get usuarioId => text().nullable()();

  DateTimeColumn get actualizadoEn => dateTime()();

  BoolColumn get pendienteSync => boolean().withDefault(const Constant(true))();

  TextColumn get ultimoError => text().nullable()();

  BoolColumn get rechazado => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {entrenamientoId};
}

/// Un punto del recorrido que la base todavía no aceptó.
@DataClassName('FilaPunto')
class PuntosLocales extends Table {
  TextColumn get entrenamientoId => text().references(
    RecorridosLocales,
    #entrenamientoId,
    onDelete: KeyAction.cascade,
  )();

  /// Su `orden_secuencia`: junto al entrenamiento identifica el punto, así
  /// que repetirlo no lo duplica.
  IntColumn get orden => integer()();

  IntColumn get tramo => integer()();

  RealColumn get latitud => real()();

  RealColumn get longitud => real()();

  DateTimeColumn get capturadoEn => dateTime()();

  @override
  Set<Column> get primaryKey => {entrenamientoId, orden};
}

/// La base SQLite del teléfono (Drift, Desarrollo Móvil). Hoy guarda los
/// recorridos que esperan subir a Supabase.
///
/// `base_local.g.dart` lo genera Drift. Después de cambiar una tabla:
/// `dart run build_runner build --delete-conflicting-outputs`, subir
/// `schemaVersion` y escribir la migración.
@DriftDatabase(tables: [RecorridosLocales, PuntosLocales])
class BaseLocal extends _$BaseLocal {
  /// Las pruebas le pasan `NativeDatabase.memory()`.
  BaseLocal(super.e);

  /// La del teléfono, en la carpeta de la app.
  BaseLocal.enTelefono() : super(driftDatabase(name: 'traza_local'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    // SQLite no aplica las llaves foráneas si no se le pide.
    beforeOpen: (_) => customStatement('PRAGMA foreign_keys = ON'),
  );
}

/// Una sola base para toda la app; se cierra con ella.
final baseLocalProvider = Provider<BaseLocal>((ref) {
  final base = BaseLocal.enTelefono();
  ref.onDispose(base.close);
  return base;
});
