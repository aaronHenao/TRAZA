import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:traza/services/almacen_recorrido.dart';
import 'package:traza/services/recorrido_provider.dart'
    show repositorioPuntosGpsProvider;
import 'package:traza/services/reenvio_recorridos.dart';

import '../utiles/almacen_recorrido_falso.dart';
import '../utiles/repositorio_puntos_gps_falso.dart';

/// Subir al abrir la app lo que quedó sin enviar (SCRUM-292).
///
/// Es lo que cierra la deuda: sin esto, un recorrido que se quedó en disco
/// porque la red no volvió antes de cerrar la app se quedaría ahí para
/// siempre.
void main() {
  late AlmacenRecorridoFalso almacen;
  late RepositorioPuntosGpsFalso repositorio;
  late ProviderContainer container;

  setUp(() {
    almacen = AlmacenRecorridoFalso();
    repositorio = RepositorioPuntosGpsFalso();
    container = ProviderContainer(
      overrides: [
        almacenRecorridoProvider.overrideWithValue(almacen),
        repositorioPuntosGpsProvider.overrideWithValue(repositorio),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<int> reintentar() => container.read(reenvioRecorridosProvider.future);

  /// Un recorrido que quedó a medio subir en una sesión anterior.
  void dejarPendiente(
    String entrenamientoId,
    int cuantos, {
    int enviados = -1,
  }) {
    almacen.sembrar(entrenamientoId, [
      for (var orden = 0; orden < cuantos; orden++)
        puntoPendienteDePrueba(orden: orden),
    ], enviados: enviados);
  }

  test('sin nada pendiente no toca la red', () async {
    expect(await reintentar(), 0);

    expect(repositorio.intentos, 0);
  });

  test('sube lo que quedó de una sesión anterior', () async {
    dejarPendiente('ent-1', 12);

    expect(await reintentar(), 1);

    expect(repositorio.puntosDe('ent-1'), hasLength(12));
  });

  test('solo sube lo que la base no tenía ya', () async {
    // Los 8 primeros entraron antes de que se cayera la red.
    dejarPendiente('ent-1', 12, enviados: 7);

    await reintentar();

    expect(repositorio.lotes.single.ordenes, [8, 9, 10, 11]);
  });

  test('una vez subido, deja de ocupar el disco', () async {
    dejarPendiente('ent-1', 5);

    await reintentar();

    expect(almacen.olvidados, ['ent-1']);
    expect(await almacen.conPendientes(), isEmpty);
  });

  test('sube todos los recorridos que haya, no solo el último', () async {
    dejarPendiente('ent-1', 3);
    dejarPendiente('ent-2', 4);

    expect(await reintentar(), 2);

    expect(repositorio.puntosDe('ent-1'), hasLength(3));
    expect(repositorio.puntosDe('ent-2'), hasLength(4));
  });

  test(
    'si la red sigue caída, el recorrido se queda para la próxima',
    () async {
      dejarPendiente('ent-1', 5);
      repositorio.fallar = true;

      expect(await reintentar(), 0);

      // Lo importante: no se borró.
      expect(almacen.olvidados, isEmpty);
      expect(await almacen.pendientes('ent-1'), hasLength(5));
    },
  );

  test('un entrenamiento que ya no existe se descarta en vez de reintentarlo '
      'siempre', () async {
    dejarPendiente('ent-borrado', 5);
    repositorio.fallar = true;
    // 23503: la clave foránea no encuentra el entrenamiento.
    repositorio.error = const PostgrestException(
      message: 'insert or update violates foreign key constraint',
      code: '23503',
    );

    expect(await reintentar(), 0);

    expect(almacen.olvidados, ['ent-borrado']);
    expect(await almacen.conPendientes(), isEmpty);
  });

  test('un recorrido de otro usuario se descarta igual', () async {
    dejarPendiente('ent-ajeno', 5);
    repositorio.fallar = true;
    // 42501: la policy no deja escribir en ese entrenamiento.
    repositorio.error = const PostgrestException(
      message: 'new row violates row-level security policy',
      code: '42501',
    );

    await reintentar();

    expect(almacen.olvidados, ['ent-ajeno']);
  });

  test('si no se puede ni mirar el disco, no revienta la portada', () async {
    almacen.error = Exception('disco no disponible');

    expect(await reintentar(), 0);
  });
}
