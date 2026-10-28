import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../models/punto_pendiente.dart';

/// Dónde esperan los puntos del recorrido hasta que la base los acepta
/// (SCRUM-292).
///
/// Antes vivían solo en memoria y se enviaban todos al finalizar: una caída
/// de red en ese momento se llevaba el recorrido entero, y salir de la
/// pantalla o que el sistema matara la app lo remataba. Ahora cada punto se
/// escribe según se captura y solo se borra cuando ya está guardado.
///
/// Guarda puntos ya numerados ([PuntoPendiente]): el orden y el tramo se
/// deciden al capturarlos, no al enviarlos.
abstract interface class AlmacenRecorrido {
  /// Añade [punto] al recorrido de [entrenamientoId].
  Future<void> anadir(String entrenamientoId, PuntoPendiente punto);

  /// Los puntos de [entrenamientoId] que la base todavía no aceptó, en orden
  /// de captura.
  Future<List<PuntoPendiente>> pendientes(String entrenamientoId);

  /// Da por guardados los puntos hasta [hastaOrden] incluido. Los siguientes
  /// siguen pendientes.
  Future<void> marcarEnviados(String entrenamientoId, int hastaOrden);

  /// Borra lo que quede del recorrido de [entrenamientoId]: ya está entero
  /// en la base, o se descartó la actividad.
  Future<void> olvidar(String entrenamientoId);

  /// Los entrenamientos con puntos sin enviar, para reintentarlos
  /// (criterio del reenvío al abrir la app).
  Future<List<String>> conPendientes();
}

/// Almacén real. Las pruebas lo sustituyen por uno en memoria.
final almacenRecorridoProvider = Provider<AlmacenRecorrido>(
  (ref) => AlmacenRecorridoEnArchivos(),
);

/// Un archivo por entrenamiento, una línea por punto (JSONL).
///
/// Se eligió añadir al final en vez de reescribir un documento entero
/// porque se escribe una vez por punto: añadir una línea no depende de lo
/// largo que sea el recorrido.
///
/// Junto a él, un archivo diminuto con hasta qué orden está guardado en la
/// base. Se reescribe entero, pero es un número.
///
/// Si la app muere a mitad de una escritura, la última línea queda cortada;
/// al leer se descarta y se pierde ese punto, no el recorrido.
class AlmacenRecorridoEnArchivos implements AlmacenRecorrido {
  AlmacenRecorridoEnArchivos({Future<Directory> Function()? carpetaBase})
    : _carpetaBase = carpetaBase ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _carpetaBase;

  static const carpeta = 'recorridos';
  static const extensionPuntos = '.jsonl';
  static const extensionEnviados = '.enviados';

  /// Nada de lo que se envía al disco se solapa: cada operación espera a la
  /// anterior. Sin esto, dos puntos seguidos podrían entrelazar sus líneas.
  Future<void> _cola = Future.value();

  Future<T> _enOrden<T>(Future<T> Function() tarea) {
    final resultado = _cola.then((_) => tarea());
    // La cola solo encadena; que una tarea falle no debe romper las
    // siguientes.
    _cola = resultado.then((_) {}, onError: (_) {});
    return resultado;
  }

  Future<Directory> _carpeta() async {
    final base = await _carpetaBase();
    final destino = Directory('${base.path}/$carpeta');
    if (!await destino.exists()) await destino.create(recursive: true);
    return destino;
  }

  Future<File> _archivo(String entrenamientoId, String extension) async =>
      File('${(await _carpeta()).path}/$entrenamientoId$extension');

  @override
  Future<void> anadir(String entrenamientoId, PuntoPendiente punto) {
    return _enOrden(() async {
      final archivo = await _archivo(entrenamientoId, extensionPuntos);
      await archivo.writeAsString(
        '${jsonEncode(punto.aJson())}\n',
        mode: FileMode.writeOnlyAppend,
        flush: true,
      );
    });
  }

  @override
  Future<List<PuntoPendiente>> pendientes(String entrenamientoId) {
    return _enOrden(() async {
      final archivo = await _archivo(entrenamientoId, extensionPuntos);
      if (!await archivo.exists()) return const <PuntoPendiente>[];

      final enviados = await _hastaDondeEnviado(entrenamientoId);
      final puntos = <PuntoPendiente>[];
      for (final linea in await archivo.readAsLines()) {
        if (linea.trim().isEmpty) continue;
        final punto = _leer(linea);
        if (punto != null && punto.orden > enviados) puntos.add(punto);
      }
      puntos.sort((a, b) => a.orden.compareTo(b.orden));
      return puntos;
    });
  }

  @override
  Future<void> marcarEnviados(String entrenamientoId, int hastaOrden) {
    return _enOrden(() async {
      final archivo = await _archivo(entrenamientoId, extensionEnviados);
      await archivo.writeAsString('$hastaOrden', flush: true);
    });
  }

  @override
  Future<void> olvidar(String entrenamientoId) {
    return _enOrden(() async {
      for (final extension in const [extensionPuntos, extensionEnviados]) {
        final archivo = await _archivo(entrenamientoId, extension);
        if (await archivo.exists()) await archivo.delete();
      }
    });
  }

  @override
  Future<List<String>> conPendientes() {
    return _enOrden(() async {
      final carpeta = await _carpeta();
      final ids = <String>[];
      await for (final entrada in carpeta.list()) {
        final nombre = entrada.path.split(RegExp(r'[/\\]')).last;
        if (!nombre.endsWith(extensionPuntos)) continue;
        ids.add(nombre.substring(0, nombre.length - extensionPuntos.length));
      }
      ids.sort();
      return ids;
    });
  }

  /// El último orden que la base ya tiene, o -1 si no hay nada enviado.
  Future<int> _hastaDondeEnviado(String entrenamientoId) async {
    final archivo = await _archivo(entrenamientoId, extensionEnviados);
    if (!await archivo.exists()) return -1;
    return int.tryParse((await archivo.readAsString()).trim()) ?? -1;
  }

  static PuntoPendiente? _leer(String linea) {
    try {
      return PuntoPendiente.desdeJson(jsonDecode(linea));
    } catch (error) {
      // La última línea de un recorrido que murió a medias.
      debugPrint('Línea ilegible en el recorrido guardado: $error');
      return null;
    }
  }
}
