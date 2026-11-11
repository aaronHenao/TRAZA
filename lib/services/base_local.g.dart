// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'base_local.dart';

// ignore_for_file: type=lint
class $RecorridosLocalesTable extends RecorridosLocales
    with TableInfo<$RecorridosLocalesTable, FilaRecorrido> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecorridosLocalesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _entrenamientoIdMeta = const VerificationMeta(
    'entrenamientoId',
  );
  @override
  late final GeneratedColumn<String> entrenamientoId = GeneratedColumn<String>(
    'entrenamiento_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _usuarioIdMeta = const VerificationMeta(
    'usuarioId',
  );
  @override
  late final GeneratedColumn<String> usuarioId = GeneratedColumn<String>(
    'usuario_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _actualizadoEnMeta = const VerificationMeta(
    'actualizadoEn',
  );
  @override
  late final GeneratedColumn<DateTime> actualizadoEn =
      GeneratedColumn<DateTime>(
        'actualizado_en',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _pendienteSyncMeta = const VerificationMeta(
    'pendienteSync',
  );
  @override
  late final GeneratedColumn<bool> pendienteSync = GeneratedColumn<bool>(
    'pendiente_sync',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("pendiente_sync" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _ultimoErrorMeta = const VerificationMeta(
    'ultimoError',
  );
  @override
  late final GeneratedColumn<String> ultimoError = GeneratedColumn<String>(
    'ultimo_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rechazadoMeta = const VerificationMeta(
    'rechazado',
  );
  @override
  late final GeneratedColumn<bool> rechazado = GeneratedColumn<bool>(
    'rechazado',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("rechazado" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    entrenamientoId,
    usuarioId,
    actualizadoEn,
    pendienteSync,
    ultimoError,
    rechazado,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recorridos_locales';
  @override
  VerificationContext validateIntegrity(
    Insertable<FilaRecorrido> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('entrenamiento_id')) {
      context.handle(
        _entrenamientoIdMeta,
        entrenamientoId.isAcceptableOrUnknown(
          data['entrenamiento_id']!,
          _entrenamientoIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_entrenamientoIdMeta);
    }
    if (data.containsKey('usuario_id')) {
      context.handle(
        _usuarioIdMeta,
        usuarioId.isAcceptableOrUnknown(data['usuario_id']!, _usuarioIdMeta),
      );
    }
    if (data.containsKey('actualizado_en')) {
      context.handle(
        _actualizadoEnMeta,
        actualizadoEn.isAcceptableOrUnknown(
          data['actualizado_en']!,
          _actualizadoEnMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_actualizadoEnMeta);
    }
    if (data.containsKey('pendiente_sync')) {
      context.handle(
        _pendienteSyncMeta,
        pendienteSync.isAcceptableOrUnknown(
          data['pendiente_sync']!,
          _pendienteSyncMeta,
        ),
      );
    }
    if (data.containsKey('ultimo_error')) {
      context.handle(
        _ultimoErrorMeta,
        ultimoError.isAcceptableOrUnknown(
          data['ultimo_error']!,
          _ultimoErrorMeta,
        ),
      );
    }
    if (data.containsKey('rechazado')) {
      context.handle(
        _rechazadoMeta,
        rechazado.isAcceptableOrUnknown(data['rechazado']!, _rechazadoMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {entrenamientoId};
  @override
  FilaRecorrido map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FilaRecorrido(
      entrenamientoId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entrenamiento_id'],
      )!,
      usuarioId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}usuario_id'],
      ),
      actualizadoEn: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}actualizado_en'],
      )!,
      pendienteSync: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}pendiente_sync'],
      )!,
      ultimoError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ultimo_error'],
      ),
      rechazado: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}rechazado'],
      )!,
    );
  }

  @override
  $RecorridosLocalesTable createAlias(String alias) {
    return $RecorridosLocalesTable(attachedDatabase, alias);
  }
}

class FilaRecorrido extends DataClass implements Insertable<FilaRecorrido> {
  /// El id del entrenamiento en Supabase: estable, el mismo aquí y allá.
  final String entrenamientoId;

  /// La cuenta dueña. Null en lo importado de los archivos de antes.
  final String? usuarioId;
  final DateTime actualizadoEn;
  final bool pendienteSync;
  final String? ultimoError;
  final bool rechazado;
  const FilaRecorrido({
    required this.entrenamientoId,
    this.usuarioId,
    required this.actualizadoEn,
    required this.pendienteSync,
    this.ultimoError,
    required this.rechazado,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['entrenamiento_id'] = Variable<String>(entrenamientoId);
    if (!nullToAbsent || usuarioId != null) {
      map['usuario_id'] = Variable<String>(usuarioId);
    }
    map['actualizado_en'] = Variable<DateTime>(actualizadoEn);
    map['pendiente_sync'] = Variable<bool>(pendienteSync);
    if (!nullToAbsent || ultimoError != null) {
      map['ultimo_error'] = Variable<String>(ultimoError);
    }
    map['rechazado'] = Variable<bool>(rechazado);
    return map;
  }

  RecorridosLocalesCompanion toCompanion(bool nullToAbsent) {
    return RecorridosLocalesCompanion(
      entrenamientoId: Value(entrenamientoId),
      usuarioId: usuarioId == null && nullToAbsent
          ? const Value.absent()
          : Value(usuarioId),
      actualizadoEn: Value(actualizadoEn),
      pendienteSync: Value(pendienteSync),
      ultimoError: ultimoError == null && nullToAbsent
          ? const Value.absent()
          : Value(ultimoError),
      rechazado: Value(rechazado),
    );
  }

  factory FilaRecorrido.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FilaRecorrido(
      entrenamientoId: serializer.fromJson<String>(json['entrenamientoId']),
      usuarioId: serializer.fromJson<String?>(json['usuarioId']),
      actualizadoEn: serializer.fromJson<DateTime>(json['actualizadoEn']),
      pendienteSync: serializer.fromJson<bool>(json['pendienteSync']),
      ultimoError: serializer.fromJson<String?>(json['ultimoError']),
      rechazado: serializer.fromJson<bool>(json['rechazado']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'entrenamientoId': serializer.toJson<String>(entrenamientoId),
      'usuarioId': serializer.toJson<String?>(usuarioId),
      'actualizadoEn': serializer.toJson<DateTime>(actualizadoEn),
      'pendienteSync': serializer.toJson<bool>(pendienteSync),
      'ultimoError': serializer.toJson<String?>(ultimoError),
      'rechazado': serializer.toJson<bool>(rechazado),
    };
  }

  FilaRecorrido copyWith({
    String? entrenamientoId,
    Value<String?> usuarioId = const Value.absent(),
    DateTime? actualizadoEn,
    bool? pendienteSync,
    Value<String?> ultimoError = const Value.absent(),
    bool? rechazado,
  }) => FilaRecorrido(
    entrenamientoId: entrenamientoId ?? this.entrenamientoId,
    usuarioId: usuarioId.present ? usuarioId.value : this.usuarioId,
    actualizadoEn: actualizadoEn ?? this.actualizadoEn,
    pendienteSync: pendienteSync ?? this.pendienteSync,
    ultimoError: ultimoError.present ? ultimoError.value : this.ultimoError,
    rechazado: rechazado ?? this.rechazado,
  );
  FilaRecorrido copyWithCompanion(RecorridosLocalesCompanion data) {
    return FilaRecorrido(
      entrenamientoId: data.entrenamientoId.present
          ? data.entrenamientoId.value
          : this.entrenamientoId,
      usuarioId: data.usuarioId.present ? data.usuarioId.value : this.usuarioId,
      actualizadoEn: data.actualizadoEn.present
          ? data.actualizadoEn.value
          : this.actualizadoEn,
      pendienteSync: data.pendienteSync.present
          ? data.pendienteSync.value
          : this.pendienteSync,
      ultimoError: data.ultimoError.present
          ? data.ultimoError.value
          : this.ultimoError,
      rechazado: data.rechazado.present ? data.rechazado.value : this.rechazado,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FilaRecorrido(')
          ..write('entrenamientoId: $entrenamientoId, ')
          ..write('usuarioId: $usuarioId, ')
          ..write('actualizadoEn: $actualizadoEn, ')
          ..write('pendienteSync: $pendienteSync, ')
          ..write('ultimoError: $ultimoError, ')
          ..write('rechazado: $rechazado')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    entrenamientoId,
    usuarioId,
    actualizadoEn,
    pendienteSync,
    ultimoError,
    rechazado,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FilaRecorrido &&
          other.entrenamientoId == this.entrenamientoId &&
          other.usuarioId == this.usuarioId &&
          other.actualizadoEn == this.actualizadoEn &&
          other.pendienteSync == this.pendienteSync &&
          other.ultimoError == this.ultimoError &&
          other.rechazado == this.rechazado);
}

class RecorridosLocalesCompanion extends UpdateCompanion<FilaRecorrido> {
  final Value<String> entrenamientoId;
  final Value<String?> usuarioId;
  final Value<DateTime> actualizadoEn;
  final Value<bool> pendienteSync;
  final Value<String?> ultimoError;
  final Value<bool> rechazado;
  final Value<int> rowid;
  const RecorridosLocalesCompanion({
    this.entrenamientoId = const Value.absent(),
    this.usuarioId = const Value.absent(),
    this.actualizadoEn = const Value.absent(),
    this.pendienteSync = const Value.absent(),
    this.ultimoError = const Value.absent(),
    this.rechazado = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RecorridosLocalesCompanion.insert({
    required String entrenamientoId,
    this.usuarioId = const Value.absent(),
    required DateTime actualizadoEn,
    this.pendienteSync = const Value.absent(),
    this.ultimoError = const Value.absent(),
    this.rechazado = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : entrenamientoId = Value(entrenamientoId),
       actualizadoEn = Value(actualizadoEn);
  static Insertable<FilaRecorrido> custom({
    Expression<String>? entrenamientoId,
    Expression<String>? usuarioId,
    Expression<DateTime>? actualizadoEn,
    Expression<bool>? pendienteSync,
    Expression<String>? ultimoError,
    Expression<bool>? rechazado,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (entrenamientoId != null) 'entrenamiento_id': entrenamientoId,
      if (usuarioId != null) 'usuario_id': usuarioId,
      if (actualizadoEn != null) 'actualizado_en': actualizadoEn,
      if (pendienteSync != null) 'pendiente_sync': pendienteSync,
      if (ultimoError != null) 'ultimo_error': ultimoError,
      if (rechazado != null) 'rechazado': rechazado,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RecorridosLocalesCompanion copyWith({
    Value<String>? entrenamientoId,
    Value<String?>? usuarioId,
    Value<DateTime>? actualizadoEn,
    Value<bool>? pendienteSync,
    Value<String?>? ultimoError,
    Value<bool>? rechazado,
    Value<int>? rowid,
  }) {
    return RecorridosLocalesCompanion(
      entrenamientoId: entrenamientoId ?? this.entrenamientoId,
      usuarioId: usuarioId ?? this.usuarioId,
      actualizadoEn: actualizadoEn ?? this.actualizadoEn,
      pendienteSync: pendienteSync ?? this.pendienteSync,
      ultimoError: ultimoError ?? this.ultimoError,
      rechazado: rechazado ?? this.rechazado,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (entrenamientoId.present) {
      map['entrenamiento_id'] = Variable<String>(entrenamientoId.value);
    }
    if (usuarioId.present) {
      map['usuario_id'] = Variable<String>(usuarioId.value);
    }
    if (actualizadoEn.present) {
      map['actualizado_en'] = Variable<DateTime>(actualizadoEn.value);
    }
    if (pendienteSync.present) {
      map['pendiente_sync'] = Variable<bool>(pendienteSync.value);
    }
    if (ultimoError.present) {
      map['ultimo_error'] = Variable<String>(ultimoError.value);
    }
    if (rechazado.present) {
      map['rechazado'] = Variable<bool>(rechazado.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecorridosLocalesCompanion(')
          ..write('entrenamientoId: $entrenamientoId, ')
          ..write('usuarioId: $usuarioId, ')
          ..write('actualizadoEn: $actualizadoEn, ')
          ..write('pendienteSync: $pendienteSync, ')
          ..write('ultimoError: $ultimoError, ')
          ..write('rechazado: $rechazado, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PuntosLocalesTable extends PuntosLocales
    with TableInfo<$PuntosLocalesTable, FilaPunto> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PuntosLocalesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _entrenamientoIdMeta = const VerificationMeta(
    'entrenamientoId',
  );
  @override
  late final GeneratedColumn<String> entrenamientoId = GeneratedColumn<String>(
    'entrenamiento_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES recorridos_locales (entrenamiento_id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _ordenMeta = const VerificationMeta('orden');
  @override
  late final GeneratedColumn<int> orden = GeneratedColumn<int>(
    'orden',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tramoMeta = const VerificationMeta('tramo');
  @override
  late final GeneratedColumn<int> tramo = GeneratedColumn<int>(
    'tramo',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _latitudMeta = const VerificationMeta(
    'latitud',
  );
  @override
  late final GeneratedColumn<double> latitud = GeneratedColumn<double>(
    'latitud',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _longitudMeta = const VerificationMeta(
    'longitud',
  );
  @override
  late final GeneratedColumn<double> longitud = GeneratedColumn<double>(
    'longitud',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _capturadoEnMeta = const VerificationMeta(
    'capturadoEn',
  );
  @override
  late final GeneratedColumn<DateTime> capturadoEn = GeneratedColumn<DateTime>(
    'capturado_en',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    entrenamientoId,
    orden,
    tramo,
    latitud,
    longitud,
    capturadoEn,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'puntos_locales';
  @override
  VerificationContext validateIntegrity(
    Insertable<FilaPunto> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('entrenamiento_id')) {
      context.handle(
        _entrenamientoIdMeta,
        entrenamientoId.isAcceptableOrUnknown(
          data['entrenamiento_id']!,
          _entrenamientoIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_entrenamientoIdMeta);
    }
    if (data.containsKey('orden')) {
      context.handle(
        _ordenMeta,
        orden.isAcceptableOrUnknown(data['orden']!, _ordenMeta),
      );
    } else if (isInserting) {
      context.missing(_ordenMeta);
    }
    if (data.containsKey('tramo')) {
      context.handle(
        _tramoMeta,
        tramo.isAcceptableOrUnknown(data['tramo']!, _tramoMeta),
      );
    } else if (isInserting) {
      context.missing(_tramoMeta);
    }
    if (data.containsKey('latitud')) {
      context.handle(
        _latitudMeta,
        latitud.isAcceptableOrUnknown(data['latitud']!, _latitudMeta),
      );
    } else if (isInserting) {
      context.missing(_latitudMeta);
    }
    if (data.containsKey('longitud')) {
      context.handle(
        _longitudMeta,
        longitud.isAcceptableOrUnknown(data['longitud']!, _longitudMeta),
      );
    } else if (isInserting) {
      context.missing(_longitudMeta);
    }
    if (data.containsKey('capturado_en')) {
      context.handle(
        _capturadoEnMeta,
        capturadoEn.isAcceptableOrUnknown(
          data['capturado_en']!,
          _capturadoEnMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_capturadoEnMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {entrenamientoId, orden};
  @override
  FilaPunto map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FilaPunto(
      entrenamientoId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entrenamiento_id'],
      )!,
      orden: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}orden'],
      )!,
      tramo: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tramo'],
      )!,
      latitud: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitud'],
      )!,
      longitud: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitud'],
      )!,
      capturadoEn: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}capturado_en'],
      )!,
    );
  }

  @override
  $PuntosLocalesTable createAlias(String alias) {
    return $PuntosLocalesTable(attachedDatabase, alias);
  }
}

class FilaPunto extends DataClass implements Insertable<FilaPunto> {
  final String entrenamientoId;

  /// Su `orden_secuencia`: junto al entrenamiento identifica el punto, así
  /// que repetirlo no lo duplica.
  final int orden;
  final int tramo;
  final double latitud;
  final double longitud;
  final DateTime capturadoEn;
  const FilaPunto({
    required this.entrenamientoId,
    required this.orden,
    required this.tramo,
    required this.latitud,
    required this.longitud,
    required this.capturadoEn,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['entrenamiento_id'] = Variable<String>(entrenamientoId);
    map['orden'] = Variable<int>(orden);
    map['tramo'] = Variable<int>(tramo);
    map['latitud'] = Variable<double>(latitud);
    map['longitud'] = Variable<double>(longitud);
    map['capturado_en'] = Variable<DateTime>(capturadoEn);
    return map;
  }

  PuntosLocalesCompanion toCompanion(bool nullToAbsent) {
    return PuntosLocalesCompanion(
      entrenamientoId: Value(entrenamientoId),
      orden: Value(orden),
      tramo: Value(tramo),
      latitud: Value(latitud),
      longitud: Value(longitud),
      capturadoEn: Value(capturadoEn),
    );
  }

  factory FilaPunto.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FilaPunto(
      entrenamientoId: serializer.fromJson<String>(json['entrenamientoId']),
      orden: serializer.fromJson<int>(json['orden']),
      tramo: serializer.fromJson<int>(json['tramo']),
      latitud: serializer.fromJson<double>(json['latitud']),
      longitud: serializer.fromJson<double>(json['longitud']),
      capturadoEn: serializer.fromJson<DateTime>(json['capturadoEn']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'entrenamientoId': serializer.toJson<String>(entrenamientoId),
      'orden': serializer.toJson<int>(orden),
      'tramo': serializer.toJson<int>(tramo),
      'latitud': serializer.toJson<double>(latitud),
      'longitud': serializer.toJson<double>(longitud),
      'capturadoEn': serializer.toJson<DateTime>(capturadoEn),
    };
  }

  FilaPunto copyWith({
    String? entrenamientoId,
    int? orden,
    int? tramo,
    double? latitud,
    double? longitud,
    DateTime? capturadoEn,
  }) => FilaPunto(
    entrenamientoId: entrenamientoId ?? this.entrenamientoId,
    orden: orden ?? this.orden,
    tramo: tramo ?? this.tramo,
    latitud: latitud ?? this.latitud,
    longitud: longitud ?? this.longitud,
    capturadoEn: capturadoEn ?? this.capturadoEn,
  );
  FilaPunto copyWithCompanion(PuntosLocalesCompanion data) {
    return FilaPunto(
      entrenamientoId: data.entrenamientoId.present
          ? data.entrenamientoId.value
          : this.entrenamientoId,
      orden: data.orden.present ? data.orden.value : this.orden,
      tramo: data.tramo.present ? data.tramo.value : this.tramo,
      latitud: data.latitud.present ? data.latitud.value : this.latitud,
      longitud: data.longitud.present ? data.longitud.value : this.longitud,
      capturadoEn: data.capturadoEn.present
          ? data.capturadoEn.value
          : this.capturadoEn,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FilaPunto(')
          ..write('entrenamientoId: $entrenamientoId, ')
          ..write('orden: $orden, ')
          ..write('tramo: $tramo, ')
          ..write('latitud: $latitud, ')
          ..write('longitud: $longitud, ')
          ..write('capturadoEn: $capturadoEn')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    entrenamientoId,
    orden,
    tramo,
    latitud,
    longitud,
    capturadoEn,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FilaPunto &&
          other.entrenamientoId == this.entrenamientoId &&
          other.orden == this.orden &&
          other.tramo == this.tramo &&
          other.latitud == this.latitud &&
          other.longitud == this.longitud &&
          other.capturadoEn == this.capturadoEn);
}

class PuntosLocalesCompanion extends UpdateCompanion<FilaPunto> {
  final Value<String> entrenamientoId;
  final Value<int> orden;
  final Value<int> tramo;
  final Value<double> latitud;
  final Value<double> longitud;
  final Value<DateTime> capturadoEn;
  final Value<int> rowid;
  const PuntosLocalesCompanion({
    this.entrenamientoId = const Value.absent(),
    this.orden = const Value.absent(),
    this.tramo = const Value.absent(),
    this.latitud = const Value.absent(),
    this.longitud = const Value.absent(),
    this.capturadoEn = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PuntosLocalesCompanion.insert({
    required String entrenamientoId,
    required int orden,
    required int tramo,
    required double latitud,
    required double longitud,
    required DateTime capturadoEn,
    this.rowid = const Value.absent(),
  }) : entrenamientoId = Value(entrenamientoId),
       orden = Value(orden),
       tramo = Value(tramo),
       latitud = Value(latitud),
       longitud = Value(longitud),
       capturadoEn = Value(capturadoEn);
  static Insertable<FilaPunto> custom({
    Expression<String>? entrenamientoId,
    Expression<int>? orden,
    Expression<int>? tramo,
    Expression<double>? latitud,
    Expression<double>? longitud,
    Expression<DateTime>? capturadoEn,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (entrenamientoId != null) 'entrenamiento_id': entrenamientoId,
      if (orden != null) 'orden': orden,
      if (tramo != null) 'tramo': tramo,
      if (latitud != null) 'latitud': latitud,
      if (longitud != null) 'longitud': longitud,
      if (capturadoEn != null) 'capturado_en': capturadoEn,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PuntosLocalesCompanion copyWith({
    Value<String>? entrenamientoId,
    Value<int>? orden,
    Value<int>? tramo,
    Value<double>? latitud,
    Value<double>? longitud,
    Value<DateTime>? capturadoEn,
    Value<int>? rowid,
  }) {
    return PuntosLocalesCompanion(
      entrenamientoId: entrenamientoId ?? this.entrenamientoId,
      orden: orden ?? this.orden,
      tramo: tramo ?? this.tramo,
      latitud: latitud ?? this.latitud,
      longitud: longitud ?? this.longitud,
      capturadoEn: capturadoEn ?? this.capturadoEn,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (entrenamientoId.present) {
      map['entrenamiento_id'] = Variable<String>(entrenamientoId.value);
    }
    if (orden.present) {
      map['orden'] = Variable<int>(orden.value);
    }
    if (tramo.present) {
      map['tramo'] = Variable<int>(tramo.value);
    }
    if (latitud.present) {
      map['latitud'] = Variable<double>(latitud.value);
    }
    if (longitud.present) {
      map['longitud'] = Variable<double>(longitud.value);
    }
    if (capturadoEn.present) {
      map['capturado_en'] = Variable<DateTime>(capturadoEn.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PuntosLocalesCompanion(')
          ..write('entrenamientoId: $entrenamientoId, ')
          ..write('orden: $orden, ')
          ..write('tramo: $tramo, ')
          ..write('latitud: $latitud, ')
          ..write('longitud: $longitud, ')
          ..write('capturadoEn: $capturadoEn, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$BaseLocal extends GeneratedDatabase {
  _$BaseLocal(QueryExecutor e) : super(e);
  $BaseLocalManager get managers => $BaseLocalManager(this);
  late final $RecorridosLocalesTable recorridosLocales =
      $RecorridosLocalesTable(this);
  late final $PuntosLocalesTable puntosLocales = $PuntosLocalesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    recorridosLocales,
    puntosLocales,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'recorridos_locales',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('puntos_locales', kind: UpdateKind.delete)],
    ),
  ]);
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);
}

typedef $$RecorridosLocalesTableCreateCompanionBuilder =
    RecorridosLocalesCompanion Function({
      required String entrenamientoId,
      Value<String?> usuarioId,
      required DateTime actualizadoEn,
      Value<bool> pendienteSync,
      Value<String?> ultimoError,
      Value<bool> rechazado,
      Value<int> rowid,
    });
typedef $$RecorridosLocalesTableUpdateCompanionBuilder =
    RecorridosLocalesCompanion Function({
      Value<String> entrenamientoId,
      Value<String?> usuarioId,
      Value<DateTime> actualizadoEn,
      Value<bool> pendienteSync,
      Value<String?> ultimoError,
      Value<bool> rechazado,
      Value<int> rowid,
    });

final class $$RecorridosLocalesTableReferences
    extends
        BaseReferences<_$BaseLocal, $RecorridosLocalesTable, FilaRecorrido> {
  $$RecorridosLocalesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$PuntosLocalesTable, List<FilaPunto>>
  _puntosLocalesRefsTable(_$BaseLocal db) => MultiTypedResultKey.fromTable(
    db.puntosLocales,
    aliasName:
        'recorridos_locales__entrenamiento_id__puntos_locales__entrenamiento_id',
  );

  $$PuntosLocalesTableProcessedTableManager get puntosLocalesRefs {
    final manager = $$PuntosLocalesTableTableManager($_db, $_db.puntosLocales)
        .filter(
          (f) => f.entrenamientoId.entrenamientoId.sqlEquals(
            $_itemColumn<String>('entrenamiento_id')!,
          ),
        );

    final cache = $_typedResult.readTableOrNull(_puntosLocalesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$RecorridosLocalesTableFilterComposer
    extends Composer<_$BaseLocal, $RecorridosLocalesTable> {
  $$RecorridosLocalesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get entrenamientoId => $composableBuilder(
    column: $table.entrenamientoId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get usuarioId => $composableBuilder(
    column: $table.usuarioId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get actualizadoEn => $composableBuilder(
    column: $table.actualizadoEn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get pendienteSync => $composableBuilder(
    column: $table.pendienteSync,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ultimoError => $composableBuilder(
    column: $table.ultimoError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get rechazado => $composableBuilder(
    column: $table.rechazado,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> puntosLocalesRefs(
    Expression<bool> Function($$PuntosLocalesTableFilterComposer f) f,
  ) {
    final $$PuntosLocalesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.entrenamientoId,
      referencedTable: $db.puntosLocales,
      getReferencedColumn: (t) => t.entrenamientoId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PuntosLocalesTableFilterComposer(
            $db: $db,
            $table: $db.puntosLocales,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$RecorridosLocalesTableOrderingComposer
    extends Composer<_$BaseLocal, $RecorridosLocalesTable> {
  $$RecorridosLocalesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get entrenamientoId => $composableBuilder(
    column: $table.entrenamientoId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get usuarioId => $composableBuilder(
    column: $table.usuarioId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get actualizadoEn => $composableBuilder(
    column: $table.actualizadoEn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get pendienteSync => $composableBuilder(
    column: $table.pendienteSync,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ultimoError => $composableBuilder(
    column: $table.ultimoError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get rechazado => $composableBuilder(
    column: $table.rechazado,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RecorridosLocalesTableAnnotationComposer
    extends Composer<_$BaseLocal, $RecorridosLocalesTable> {
  $$RecorridosLocalesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get entrenamientoId => $composableBuilder(
    column: $table.entrenamientoId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get usuarioId =>
      $composableBuilder(column: $table.usuarioId, builder: (column) => column);

  GeneratedColumn<DateTime> get actualizadoEn => $composableBuilder(
    column: $table.actualizadoEn,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get pendienteSync => $composableBuilder(
    column: $table.pendienteSync,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ultimoError => $composableBuilder(
    column: $table.ultimoError,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get rechazado =>
      $composableBuilder(column: $table.rechazado, builder: (column) => column);

  Expression<T> puntosLocalesRefs<T extends Object>(
    Expression<T> Function($$PuntosLocalesTableAnnotationComposer a) f,
  ) {
    final $$PuntosLocalesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.entrenamientoId,
      referencedTable: $db.puntosLocales,
      getReferencedColumn: (t) => t.entrenamientoId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PuntosLocalesTableAnnotationComposer(
            $db: $db,
            $table: $db.puntosLocales,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$RecorridosLocalesTableTableManager
    extends
        RootTableManager<
          _$BaseLocal,
          $RecorridosLocalesTable,
          FilaRecorrido,
          $$RecorridosLocalesTableFilterComposer,
          $$RecorridosLocalesTableOrderingComposer,
          $$RecorridosLocalesTableAnnotationComposer,
          $$RecorridosLocalesTableCreateCompanionBuilder,
          $$RecorridosLocalesTableUpdateCompanionBuilder,
          (FilaRecorrido, $$RecorridosLocalesTableReferences),
          FilaRecorrido,
          PrefetchHooks Function({bool puntosLocalesRefs})
        > {
  $$RecorridosLocalesTableTableManager(
    _$BaseLocal db,
    $RecorridosLocalesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecorridosLocalesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RecorridosLocalesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RecorridosLocalesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> entrenamientoId = const Value.absent(),
                Value<String?> usuarioId = const Value.absent(),
                Value<DateTime> actualizadoEn = const Value.absent(),
                Value<bool> pendienteSync = const Value.absent(),
                Value<String?> ultimoError = const Value.absent(),
                Value<bool> rechazado = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RecorridosLocalesCompanion(
                entrenamientoId: entrenamientoId,
                usuarioId: usuarioId,
                actualizadoEn: actualizadoEn,
                pendienteSync: pendienteSync,
                ultimoError: ultimoError,
                rechazado: rechazado,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String entrenamientoId,
                Value<String?> usuarioId = const Value.absent(),
                required DateTime actualizadoEn,
                Value<bool> pendienteSync = const Value.absent(),
                Value<String?> ultimoError = const Value.absent(),
                Value<bool> rechazado = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RecorridosLocalesCompanion.insert(
                entrenamientoId: entrenamientoId,
                usuarioId: usuarioId,
                actualizadoEn: actualizadoEn,
                pendienteSync: pendienteSync,
                ultimoError: ultimoError,
                rechazado: rechazado,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$RecorridosLocalesTable, FilaRecorrido>(table),
                  $$RecorridosLocalesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({puntosLocalesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (puntosLocalesRefs) db.puntosLocales,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (puntosLocalesRefs)
                    await $_getPrefetchedDataByColumns<
                      FilaRecorrido,
                      $RecorridosLocalesTable,
                      FilaPunto,
                      $PuntosLocalesTable
                    >(
                      currentTable: table,
                      referencedTable: $$RecorridosLocalesTableReferences
                          ._puntosLocalesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$RecorridosLocalesTableReferences(
                            db,
                            table,
                            p0,
                          ).puntosLocalesRefs,
                      currentColumn: 'entrenamiento_id',
                      referencedColumn: 'entrenamiento_id',
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$RecorridosLocalesTableProcessedTableManager =
    ProcessedTableManager<
      _$BaseLocal,
      $RecorridosLocalesTable,
      FilaRecorrido,
      $$RecorridosLocalesTableFilterComposer,
      $$RecorridosLocalesTableOrderingComposer,
      $$RecorridosLocalesTableAnnotationComposer,
      $$RecorridosLocalesTableCreateCompanionBuilder,
      $$RecorridosLocalesTableUpdateCompanionBuilder,
      (FilaRecorrido, $$RecorridosLocalesTableReferences),
      FilaRecorrido,
      PrefetchHooks Function({bool puntosLocalesRefs})
    >;
typedef $$PuntosLocalesTableCreateCompanionBuilder =
    PuntosLocalesCompanion Function({
      required String entrenamientoId,
      required int orden,
      required int tramo,
      required double latitud,
      required double longitud,
      required DateTime capturadoEn,
      Value<int> rowid,
    });
typedef $$PuntosLocalesTableUpdateCompanionBuilder =
    PuntosLocalesCompanion Function({
      Value<String> entrenamientoId,
      Value<int> orden,
      Value<int> tramo,
      Value<double> latitud,
      Value<double> longitud,
      Value<DateTime> capturadoEn,
      Value<int> rowid,
    });

final class $$PuntosLocalesTableReferences
    extends BaseReferences<_$BaseLocal, $PuntosLocalesTable, FilaPunto> {
  $$PuntosLocalesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $RecorridosLocalesTable _entrenamientoIdTable(
    _$BaseLocal db,
  ) => db.recorridosLocales.createAlias(
    'puntos_locales__entrenamiento_id__recorridos_locales__entrenamiento_id',
  );

  $$RecorridosLocalesTableProcessedTableManager get entrenamientoId {
    final $_column = $_itemColumn<String>('entrenamiento_id')!;

    final manager = $$RecorridosLocalesTableTableManager(
      $_db,
      $_db.recorridosLocales,
    ).filter((f) => f.entrenamientoId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_entrenamientoIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$PuntosLocalesTableFilterComposer
    extends Composer<_$BaseLocal, $PuntosLocalesTable> {
  $$PuntosLocalesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get orden => $composableBuilder(
    column: $table.orden,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tramo => $composableBuilder(
    column: $table.tramo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get latitud => $composableBuilder(
    column: $table.latitud,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get longitud => $composableBuilder(
    column: $table.longitud,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get capturadoEn => $composableBuilder(
    column: $table.capturadoEn,
    builder: (column) => ColumnFilters(column),
  );

  $$RecorridosLocalesTableFilterComposer get entrenamientoId {
    final $$RecorridosLocalesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.entrenamientoId,
      referencedTable: $db.recorridosLocales,
      getReferencedColumn: (t) => t.entrenamientoId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecorridosLocalesTableFilterComposer(
            $db: $db,
            $table: $db.recorridosLocales,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PuntosLocalesTableOrderingComposer
    extends Composer<_$BaseLocal, $PuntosLocalesTable> {
  $$PuntosLocalesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get orden => $composableBuilder(
    column: $table.orden,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tramo => $composableBuilder(
    column: $table.tramo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get latitud => $composableBuilder(
    column: $table.latitud,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get longitud => $composableBuilder(
    column: $table.longitud,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get capturadoEn => $composableBuilder(
    column: $table.capturadoEn,
    builder: (column) => ColumnOrderings(column),
  );

  $$RecorridosLocalesTableOrderingComposer get entrenamientoId {
    final $$RecorridosLocalesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.entrenamientoId,
      referencedTable: $db.recorridosLocales,
      getReferencedColumn: (t) => t.entrenamientoId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecorridosLocalesTableOrderingComposer(
            $db: $db,
            $table: $db.recorridosLocales,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PuntosLocalesTableAnnotationComposer
    extends Composer<_$BaseLocal, $PuntosLocalesTable> {
  $$PuntosLocalesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get orden =>
      $composableBuilder(column: $table.orden, builder: (column) => column);

  GeneratedColumn<int> get tramo =>
      $composableBuilder(column: $table.tramo, builder: (column) => column);

  GeneratedColumn<double> get latitud =>
      $composableBuilder(column: $table.latitud, builder: (column) => column);

  GeneratedColumn<double> get longitud =>
      $composableBuilder(column: $table.longitud, builder: (column) => column);

  GeneratedColumn<DateTime> get capturadoEn => $composableBuilder(
    column: $table.capturadoEn,
    builder: (column) => column,
  );

  $$RecorridosLocalesTableAnnotationComposer get entrenamientoId {
    final $$RecorridosLocalesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.entrenamientoId,
          referencedTable: $db.recorridosLocales,
          getReferencedColumn: (t) => t.entrenamientoId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$RecorridosLocalesTableAnnotationComposer(
                $db: $db,
                $table: $db.recorridosLocales,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$PuntosLocalesTableTableManager
    extends
        RootTableManager<
          _$BaseLocal,
          $PuntosLocalesTable,
          FilaPunto,
          $$PuntosLocalesTableFilterComposer,
          $$PuntosLocalesTableOrderingComposer,
          $$PuntosLocalesTableAnnotationComposer,
          $$PuntosLocalesTableCreateCompanionBuilder,
          $$PuntosLocalesTableUpdateCompanionBuilder,
          (FilaPunto, $$PuntosLocalesTableReferences),
          FilaPunto,
          PrefetchHooks Function({bool entrenamientoId})
        > {
  $$PuntosLocalesTableTableManager(_$BaseLocal db, $PuntosLocalesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PuntosLocalesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PuntosLocalesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PuntosLocalesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> entrenamientoId = const Value.absent(),
                Value<int> orden = const Value.absent(),
                Value<int> tramo = const Value.absent(),
                Value<double> latitud = const Value.absent(),
                Value<double> longitud = const Value.absent(),
                Value<DateTime> capturadoEn = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PuntosLocalesCompanion(
                entrenamientoId: entrenamientoId,
                orden: orden,
                tramo: tramo,
                latitud: latitud,
                longitud: longitud,
                capturadoEn: capturadoEn,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String entrenamientoId,
                required int orden,
                required int tramo,
                required double latitud,
                required double longitud,
                required DateTime capturadoEn,
                Value<int> rowid = const Value.absent(),
              }) => PuntosLocalesCompanion.insert(
                entrenamientoId: entrenamientoId,
                orden: orden,
                tramo: tramo,
                latitud: latitud,
                longitud: longitud,
                capturadoEn: capturadoEn,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PuntosLocalesTable, FilaPunto>(table),
                  $$PuntosLocalesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({entrenamientoId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (entrenamientoId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.entrenamientoId,
                                referencedTable: $$PuntosLocalesTableReferences
                                    ._entrenamientoIdTable(db),
                                referencedColumn: $$PuntosLocalesTableReferences
                                    ._entrenamientoIdTable(db)
                                    .entrenamientoId,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$PuntosLocalesTableProcessedTableManager =
    ProcessedTableManager<
      _$BaseLocal,
      $PuntosLocalesTable,
      FilaPunto,
      $$PuntosLocalesTableFilterComposer,
      $$PuntosLocalesTableOrderingComposer,
      $$PuntosLocalesTableAnnotationComposer,
      $$PuntosLocalesTableCreateCompanionBuilder,
      $$PuntosLocalesTableUpdateCompanionBuilder,
      (FilaPunto, $$PuntosLocalesTableReferences),
      FilaPunto,
      PrefetchHooks Function({bool entrenamientoId})
    >;

class $BaseLocalManager {
  final _$BaseLocal _db;
  $BaseLocalManager(this._db);
  $$RecorridosLocalesTableTableManager get recorridosLocales =>
      $$RecorridosLocalesTableTableManager(_db, _db.recorridosLocales);
  $$PuntosLocalesTableTableManager get puntosLocales =>
      $$PuntosLocalesTableTableManager(_db, _db.puntosLocales);
}
