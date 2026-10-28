import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/punto_gps.dart';
import 'package:traza/models/punto_pendiente.dart';
import 'package:traza/services/almacen_recorrido.dart';

import '../utiles/almacen_recorrido_falso.dart';

/// El almacén en disco de los puntos del recorrido (SCRUM-292).
///
/// Escribe en una carpeta temporal de verdad: lo que se prueba aquí es
/// justamente el archivo, así que un doble no serviría de nada.
void main() {
  late Directory carpeta;
  late AlmacenRecorridoEnArchivos almacen;

  setUp(() async {
    carpeta = await Directory.systemTemp.createTemp('traza_recorrido');
    almacen = AlmacenRecorridoEnArchivos(carpetaBase: () async => carpeta);
  });

  tearDown(() async {
    if (await carpeta.exists()) await carpeta.delete(recursive: true);
  });

  Future<File> archivoDe(String id) async => File(
    '${carpeta.path}/${AlmacenRecorridoEnArchivos.carpeta}/'
    '$id${AlmacenRecorridoEnArchivos.extensionPuntos}',
  );

  test('un punto guardado se puede volver a leer igual', () async {
    final punto = puntoPendienteDePrueba(orden: 0, tramo: 1);

    await almacen.anadir('ent-1', punto);

    expect(await almacen.pendientes('ent-1'), [punto]);
  });

  test('sin nada guardado no hay pendientes', () async {
    expect(await almacen.pendientes('ent-1'), isEmpty);
  });

  test(
    'los devuelve en orden de captura aunque se guarden a destiempo',
    () async {
      for (final orden in [2, 0, 1]) {
        await almacen.anadir('ent-1', puntoPendienteDePrueba(orden: orden));
      }

      final pendientes = await almacen.pendientes('ent-1');

      expect(pendientes.map((p) => p.orden), [0, 1, 2]);
    },
  );

  test('cada entrenamiento guarda lo suyo', () async {
    await almacen.anadir('ent-1', puntoPendienteDePrueba(orden: 0));
    await almacen.anadir('ent-2', puntoPendienteDePrueba(orden: 0));
    await almacen.anadir('ent-2', puntoPendienteDePrueba(orden: 1));

    expect(await almacen.pendientes('ent-1'), hasLength(1));
    expect(await almacen.pendientes('ent-2'), hasLength(2));
  });

  test(
    'lo dado por enviado deja de estar pendiente, y lo demás sigue',
    () async {
      for (var orden = 0; orden < 5; orden++) {
        await almacen.anadir('ent-1', puntoPendienteDePrueba(orden: orden));
      }

      await almacen.marcarEnviados('ent-1', 2);

      final pendientes = await almacen.pendientes('ent-1');
      expect(pendientes.map((p) => p.orden), [3, 4]);
    },
  );

  test('marcar enviado el último no deja nada pendiente', () async {
    await almacen.anadir('ent-1', puntoPendienteDePrueba(orden: 0));

    await almacen.marcarEnviados('ent-1', 0);

    expect(await almacen.pendientes('ent-1'), isEmpty);
  });

  test('olvidar un recorrido borra sus archivos', () async {
    await almacen.anadir('ent-1', puntoPendienteDePrueba(orden: 0));
    await almacen.marcarEnviados('ent-1', 0);

    await almacen.olvidar('ent-1');

    expect(await almacen.pendientes('ent-1'), isEmpty);
    expect(await almacen.conPendientes(), isEmpty);
    expect(await (await archivoDe('ent-1')).exists(), isFalse);
  });

  test('olvidar algo que no está no falla', () async {
    await almacen.olvidar('ent-que-no-existe');
  });

  test('dice qué entrenamientos tienen algo guardado', () async {
    await almacen.anadir('ent-b', puntoPendienteDePrueba(orden: 0));
    await almacen.anadir('ent-a', puntoPendienteDePrueba(orden: 0));

    expect(await almacen.conPendientes(), ['ent-a', 'ent-b']);
  });

  test(
    'una línea cortada se descarta sin perder el resto del recorrido',
    () async {
      // Como si la app hubiera muerto a mitad de escribir el tercer punto.
      await almacen.anadir('ent-1', puntoPendienteDePrueba(orden: 0));
      await almacen.anadir('ent-1', puntoPendienteDePrueba(orden: 1));
      final archivo = await archivoDe('ent-1');
      await archivo.writeAsString(
        '{"la":6.24,"lo":-75.5,"t":"202',
        mode: FileMode.writeOnlyAppend,
      );

      final pendientes = await almacen.pendientes('ent-1');

      expect(pendientes.map((p) => p.orden), [0, 1]);
    },
  );

  test('una línea con campos que no son los esperados se descarta', () async {
    await almacen.anadir('ent-1', puntoPendienteDePrueba(orden: 0));
    final archivo = await archivoDe('ent-1');
    await archivo.writeAsString(
      '${jsonEncode({'la': 'no es un numero', 'lo': 1, 't': 'x', 'o': 1, 'tr': 0})}\n',
      mode: FileMode.writeOnlyAppend,
    );

    expect(await almacen.pendientes('ent-1'), hasLength(1));
  });

  test('guarda lo que la tabla necesita y nada más', () async {
    final punto = PuntoPendiente.de(
      PuntoGps(
        latitud: 6.2442,
        longitud: -75.5812,
        capturadoEn: DateTime.utc(2026, 10, 27, 15, 30),
        // Ni la precisión ni la velocidad se guardan: `puntos_gps` no las
        // tiene y esto se escribe una vez por punto.
        precisionMetros: 5,
        velocidadMps: 3.5,
        precisionVelocidadMps: 0.5,
      ),
      orden: 7,
      tramo: 2,
    );

    await almacen.anadir('ent-1', punto);

    final linea = (await (await archivoDe('ent-1')).readAsLines()).single;
    expect(jsonDecode(linea), {
      'la': 6.2442,
      'lo': -75.5812,
      't': '2026-10-27T15:30:00.000Z',
      'o': 7,
      'tr': 2,
    });
  });

  test('aguanta un recorrido largo sin mezclar las líneas', () async {
    // Un 10 km a un punto cada 5 m son ~2000 puntos. Si las escrituras se
    // solaparan, alguna línea saldría partida.
    final escrituras = [
      for (var orden = 0; orden < 300; orden++)
        almacen.anadir('ent-1', puntoPendienteDePrueba(orden: orden)),
    ];
    await Future.wait(escrituras);

    final pendientes = await almacen.pendientes('ent-1');
    expect(pendientes, hasLength(300));
    expect(pendientes.first.orden, 0);
    expect(pendientes.last.orden, 299);
  });
}
