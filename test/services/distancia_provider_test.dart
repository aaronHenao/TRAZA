import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/distancia_en_vivo.dart';
import 'package:traza/services/calculadora_distancia.dart';
import 'package:traza/services/cronometro_provider.dart';
import 'package:traza/services/distancia_provider.dart';
import 'package:traza/services/recorrido_provider.dart';
import 'package:traza/services/ubicacion_provider.dart';
import 'package:traza/services/ubicacion_service.dart';

import '../utiles/fuente_ubicacion_falsa.dart';
import '../utiles/reloj_falso.dart';
import '../utiles/repositorio_puntos_gps_falso.dart';

// 0.001° de latitud ≈ 111.19 m en cualquier longitud.
const double _metrosPorMiliGrado = 111.19;

void main() {
  late FuenteUbicacionFalsa fuente;
  late RelojFalso reloj;
  late ProviderContainer container;

  ProviderContainer crear({List<Override> extra = const []}) {
    final c = ProviderContainer(
      overrides: [
        relojProvider.overrideWithValue(reloj.call),
        fuenteUbicacionProvider.overrideWithValue(fuente),
        repositorioPuntosGpsProvider.overrideWithValue(
          RepositorioPuntosGpsFalso(),
        ),
        entrenamientoActualProvider.overrideWithValue(null),
        ...extra,
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// Monta el container como lo vería la pantalla de entrenamiento:
  /// cronómetro en marcha, recorrido y distancia observados.
  Future<void> montar({
    List<Override> extra = const [],
    bool observarDistancia = true,
  }) async {
    container = crear(extra: extra);
    container.listen(recorridoProvider, (_, _) {});
    if (observarDistancia) container.listen(distanciaProvider, (_, _) {});
    container.read(cronometroProvider.notifier).iniciar();
    addTearDown(() => container.read(cronometroProvider.notifier).detener());
    await pumpEventQueue();
  }

  /// Emite una lectura [segundos] después del inicio de la actividad.
  Future<void> emitir(
    double latitud, {
    required int segundos,
    double? precisionMetros = 8,
  }) async {
    fuente.emitir(
      puntoDePrueba(
        latitud: latitud,
        capturadoEn: DateTime(2026, 1, 1, 8).add(Duration(seconds: segundos)),
        precisionMetros: precisionMetros,
      ),
    );
    await pumpEventQueue();
  }

  DistanciaEnVivo distancia() => container.read(distanciaProvider);

  setUp(() {
    fuente = FuenteUbicacionFalsa();
    reloj = RelojFalso();
    addTearDown(() => fuente.cerrar());
  });

  test('empieza en 0', () async {
    await montar();

    expect(distancia().metros, 0);
    expect(distancia().kilometros, '0.00 km');
  });

  test('el primer punto fija el ancla sin sumar', () async {
    await montar();

    await emitir(6.2311, segundos: 0);

    expect(distancia().metros, 0);
  });

  test('suma entre puntos consecutivos válidos en tiempo real', () async {
    await montar();

    await emitir(6.2311, segundos: 0);
    await emitir(6.2321, segundos: 30); // +111 m
    expect(distancia().metros, closeTo(_metrosPorMiliGrado, 0.5));

    await emitir(6.2331, segundos: 60); // +111 m
    expect(distancia().metros, closeTo(2 * _metrosPorMiliGrado, 0.5));
    expect(distancia().kilometros, '0.22 km');
  });

  test('descarta ruido: precisión mala, jitter y saltos imposibles', () async {
    await montar();

    await emitir(6.2311, segundos: 0);
    // Teleport: 111 m en 1 s.
    await emitir(6.2321, segundos: 1);
    // Jitter: ~1 m respecto al ancla.
    await emitir(6.23111, segundos: 2);
    // Precisión de 40 m (peor que el tope de 30 m).
    await emitir(6.2331, segundos: 60, precisionMetros: 40);

    expect(distancia().metros, 0);
    // El teleport y el jitter llegaron al recorrido (el trazo los pinta y
    // el filtro fino es de la calculadora), pero la lectura de 40 m no:
    // esa la descarta el filtro de precisión antes de la pantalla.
    expect(container.read(recorridoProvider).puntos, hasLength(3));
  });

  test('sin lecturas del GPS la distancia es 0, no un dato vacío', () async {
    await montar();
    await pumpEventQueue();

    expect(distancia(), const DistanciaEnVivo(metros: 0));
    expect(distancia().ritmoPara(const Duration(minutes: 5)), "0'00\"");
  });

  test('si el GPS falla conserva lo acumulado y no lanza', () async {
    await montar();

    await emitir(6.2311, segundos: 0);
    await emitir(6.2321, segundos: 30); // +111 m

    fuente.fallar(StateError('GPS apagado'));
    await pumpEventQueue();

    expect(distancia().metros, closeTo(_metrosPorMiliGrado, 0.5));
  });

  test('una lectura sin precisión reportada sí cuenta', () async {
    await montar();

    await emitir(6.2311, segundos: 0, precisionMetros: null);
    await emitir(6.2321, segundos: 30, precisionMetros: null);

    expect(distancia().metros, closeTo(_metrosPorMiliGrado, 0.5));
  });

  test('no cuenta lo que el usuario se movió en pausa', () async {
    await montar();

    await emitir(6.2311, segundos: 0);
    await emitir(6.2321, segundos: 30); // +111 m

    container.read(cronometroProvider.notifier).pausar();
    // En pausa el recorrido ignora las lecturas.
    await emitir(6.2421, segundos: 300);
    expect(distancia().metros, closeTo(_metrosPorMiliGrado, 0.5));

    container.read(cronometroProvider.notifier).reanudar();
    // Primer punto tras reanudar: 1 km más lejos, pero no debe sumar.
    await emitir(6.2421, segundos: 330);
    expect(distancia().metros, closeTo(_metrosPorMiliGrado, 0.5));

    // Y desde ahí vuelve a sumar normal.
    await emitir(6.2431, segundos: 360);
    expect(distancia().metros, closeTo(2 * _metrosPorMiliGrado, 0.5));
  });

  test('ritmo usa el tiempo del cronómetro y la distancia acumulada', () async {
    await montar();

    await emitir(6.2311, segundos: 0);
    await emitir(6.2321, segundos: 30); // ≈111 m

    // 5 min para 111 m → 45'00" por km aprox.
    expect(distancia().ritmoPara(const Duration(minutes: 5)), "44'58\"");
    expect(distancia().ritmoPara(Duration.zero), "0'00\"");
  });

  test(
    'cuenta los puntos registrados antes de observar la distancia',
    () async {
      await montar(observarDistancia: false);

      await emitir(6.2311, segundos: 0);
      await emitir(6.2321, segundos: 30);

      // Recién ahora alguien observa la distancia.
      container.listen(distanciaProvider, (_, _) {});
      expect(distancia().metros, closeTo(_metrosPorMiliGrado, 0.5));
    },
  );

  test('la calculadora se puede sustituir', () async {
    // Con umbral de precisión 100 m, la lectura de 40 m sí cuenta. El
    // umbral va en la configuración de rastreo: es el mismo número para
    // el filtro de lecturas y para la calculadora (SCRUM-116).
    await montar(
      extra: [
        configuracionRastreoProvider.overrideWithValue(
          const ConfiguracionRastreo(precisionMaximaMetros: 100),
        ),
        fabricaCalculadoraDistanciaProvider.overrideWithValue(
          () => CalculadoraDistancia(precisionMaximaMetros: 100),
        ),
      ],
    );

    await emitir(6.2311, segundos: 0, precisionMetros: 40);
    await emitir(6.2321, segundos: 30, precisionMetros: 40);

    expect(distancia().metros, closeTo(_metrosPorMiliGrado, 0.5));
  });
}
