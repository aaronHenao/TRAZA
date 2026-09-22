import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/punto_gps.dart';
import 'package:traza/services/reloj_provider.dart';
import 'package:traza/services/ubicacion_provider.dart';
import 'package:traza/services/ubicacion_service.dart';

import '../utiles/fuente_ubicacion_falsa.dart';
import '../utiles/reloj_falso.dart';

void main() {
  late FuenteUbicacionFalsa fuente;
  late ProviderContainer container;

  setUp(() {
    fuente = FuenteUbicacionFalsa();
    addTearDown(() => fuente.cerrar());
    container = ProviderContainer(
      overrides: [
        fuenteUbicacionProvider.overrideWithValue(fuente),
        relojProvider.overrideWithValue(RelojFalso().call),
      ],
    );
    addTearDown(container.dispose);
  });

  /// Deja el stream observado, como hace la pantalla de entrenamiento.
  ProviderSubscription<AsyncValue<PuntoGps>> observar() =>
      container.listen(posicionEnVivoProvider, (_, _) {});

  group('posicionEnVivoProvider', () {
    test('al observarlo abre la fuente y queda esperando la primera lectura',
        () async {
      observar();
      await pumpEventQueue();

      expect(fuente.suscripcionesAbiertas, 1);
      expect(container.read(posicionEnVivoProvider).isLoading, isTrue);
    });

    test('entrega cada posición conforme el usuario avanza', () async {
      observar();

      final primero = puntoDePrueba();
      fuente.emitir(primero);
      await pumpEventQueue();
      expect(container.read(posicionEnVivoProvider).value, primero);

      final segundo = puntoDePrueba(latitud: 6.2320, longitud: -75.6110);
      fuente.emitir(segundo);
      await pumpEventQueue();
      expect(container.read(posicionEnVivoProvider).value, segundo);
    });

    test('descarta las lecturas más imprecisas que el tope configurado',
        () async {
      observar();

      fuente.emitir(puntoDePrueba(latitud: 6.9, precisionMetros: 200));
      await pumpEventQueue();
      expect(container.read(posicionEnVivoProvider).isLoading, isTrue);

      fuente.emitir(puntoDePrueba(latitud: 6.2311, precisionMetros: 12));
      await pumpEventQueue();
      expect(container.read(posicionEnVivoProvider).value!.latitud, 6.2311);
    });

    test('descarta la ultima posicion conocida si es vieja', () async {
      observar();

      fuente.emitir(puntoDePrueba(
        latitud: 6.9,
        capturadoEn: DateTime(2026, 1, 1, 7, 30),
      ));
      await pumpEventQueue();
      expect(container.read(posicionEnVivoProvider).isLoading, isTrue);

      fuente.emitir(puntoDePrueba(latitud: 6.2311));
      await pumpEventQueue();
      expect(container.read(posicionEnVivoProvider).value!.latitud, 6.2311);
    });

    test('si la fuente falla expone el error', () async {
      observar();

      fuente.fallar(StateError('GPS perdido'));
      await pumpEventQueue();

      expect(container.read(posicionEnVivoProvider).hasError, isTrue);
    });

    test('cierra la fuente cuando nadie observa la posición', () async {
      final sub = observar();
      await pumpEventQueue();
      expect(fuente.suscripcionesAbiertas, 1);

      sub.close();
      await pumpEventQueue();

      expect(fuente.suscripcionesAbiertas, 0);
    });

    test('cierra la fuente aunque aún no haya llegado la primera lectura',
        () async {
      // Riverpod por sí solo dejaría la suscripción abierta en este caso.
      final sub = observar();
      await pumpEventQueue();

      sub.close();
      await pumpEventQueue();

      expect(fuente.suscripcionesAbiertas, 0);
      expect(container.read(posicionEnVivoProvider).isLoading, isTrue);
    });

    test('abre la fuente con la configuración de rastreo del provider',
        () async {
      const configuracion = ConfiguracionRastreo(
        distanciaMinimaSistemaMetros: 7,
        altaPrecision: false,
      );
      final otro = ProviderContainer(
        overrides: [
          fuenteUbicacionProvider.overrideWithValue(fuente),
          configuracionRastreoProvider.overrideWithValue(configuracion),
          relojProvider.overrideWithValue(RelojFalso().call),
        ],
      );
      addTearDown(otro.dispose);

      otro.listen(posicionEnVivoProvider, (_, _) {});
      await pumpEventQueue();

      expect(fuente.ultimaConfiguracion, same(configuracion));
    });
  });
}
