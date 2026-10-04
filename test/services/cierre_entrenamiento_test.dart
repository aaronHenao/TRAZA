import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/insignia.dart';
import 'package:traza/models/nivel.dart';
import 'package:traza/models/recorrido.dart';
import 'package:traza/models/resumen_entrenamiento.dart';
import 'package:traza/services/entrenamiento_actual_provider.dart';
import 'package:traza/services/entrenamiento_provider.dart';
import 'package:traza/services/entrenamiento_service.dart';
import 'package:traza/services/experiencia_service.dart';
import 'package:traza/services/insignias_provider.dart';
import 'package:traza/services/insignias_service.dart';
import 'package:traza/services/mapa_progresion_provider.dart';
import 'package:traza/services/niveles_service.dart';
import 'package:traza/services/progresion_provider.dart';
import 'package:traza/services/reloj_provider.dart';

import '../utiles/experiencia_falsa.dart';
import '../utiles/insignias_falsas.dart';
import '../utiles/niveles_falso.dart';
import '../utiles/reloj_falso.dart';

/// Pruebas de la XP en el cierre del entrenamiento (SCRUM-206).
///
/// La XP la asigna el trigger de la base en el mismo cierre; lo que le toca a
/// la app es volver a leer la acumulada para que la progresión la refleje.
void main() {
  late _EntrenamientosFalso entrenamientos;
  late ExperienciaFalsa experiencia;
  late InsigniasFalsas insignias;
  late ProviderContainer container;

  setUp(() {
    entrenamientos = _EntrenamientosFalso();
    experiencia = ExperienciaFalsa(acumulada: 100);
    insignias = InsigniasFalsas(catalogo: const [_diezMil]);

    container = ProviderContainer(
      overrides: [
        entrenamientoActualProvider.overrideWithValue('e-1'),
        entrenamientoRepositoryProvider.overrideWithValue(entrenamientos),
        experienciaRepositoryProvider.overrideWithValue(experiencia),
        nivelesRepositoryProvider.overrideWithValue(
          NivelesFalso(
            catalogo: const [
              Nivel(id: 'n-1', nombre: 'Bronce', umbralExperiencia: 120),
            ],
          ),
        ),
        relojProvider.overrideWithValue(RelojFalso().call),
        insigniasRepositoryProvider.overrideWithValue(insignias),
      ],
    );
    addTearDown(container.dispose);
    // Como la pantalla de progresión abierta: la mantiene viva.
    container.listen(progresionProvider, (_, _) {});
    // Las insignias se ven en la misma pantalla (SCRUM-193).
    container.listen(insigniasProvider, (_, _) {});
  });

  Future<String?> finalizar() => container
      .read(cierreEntrenamientoProvider)
      .finalizar(
        duracion: const Duration(minutes: 30),
        recorrido: const Recorrido(),
        distanciaMetros: 5000,
      );

  test('al finalizar, la progresión vuelve a leer la XP', () async {
    final antes = await container.read(progresionProvider.future);
    expect(antes.nivelActual, isNull);

    // Lo que habría sumado el trigger al cerrar.
    experiencia.acumulada = 125;
    expect(await finalizar(), isNull);

    final despues = await container.read(progresionProvider.future);
    expect(despues.experiencia, 125);
    expect(despues.nivelActual?.nombre, 'Bronce');
    expect(experiencia.consultas, 2);
  });

  test('si el cierre no se guardó, no hay XP nueva que leer', () async {
    await container.read(progresionProvider.future);
    entrenamientos.fallar = true;

    expect(await finalizar(), isNotNull);

    await container.read(progresionProvider.future);
    expect(experiencia.consultas, 1);
  });

  group('mapa de progresión (SCRUM-226, criterio 3)', () {
    setUp(() {
      // Como el mapa abierto en su pestaña: lo mantiene vivo. Va solo en este
      // grupo para no alterar las consultas que cuentan las pruebas de arriba.
      container.listen(mapaProgresionProvider, (_, _) {});
    });

    test('al finalizar, el mapa vuelve a leer la XP y muestra la nueva '
        'posición', () async {
      final antes = await container.read(mapaProgresionProvider.future);
      expect(antes.experiencia, 100);
      expect(antes.indiceActual, 0);

      // Lo que habría sumado el trigger al cerrar: pasa Bronce (120).
      experiencia.acumulada = 125;
      expect(await finalizar(), isNull);

      final despues = await container.read(mapaProgresionProvider.future);
      expect(despues.experiencia, 125);
      expect(despues.indiceActual, 1);
      expect(despues.paradas[despues.indiceActual].nombre, 'Bronce');
    });

    test('si el cierre no se guardó, el mapa no se vuelve a leer', () async {
      final antes = await container.read(mapaProgresionProvider.future);
      expect(antes.experiencia, 100);
      entrenamientos.fallar = true;

      // Aunque la base cambiara, sin cierre no hay motivo para releer.
      experiencia.acumulada = 125;
      expect(await finalizar(), isNotNull);

      final despues = await container.read(mapaProgresionProvider.future);
      expect(despues.experiencia, 100);
      expect(despues.indiceActual, 0);
    });
  });

  group('insignias (SCRUM-193)', () {
    test('al finalizar, las insignias se vuelven a leer', () async {
      final antes = await container.read(insigniasProvider.future);
      expect(antes.single.obtenida, isFalse);
      expect(insignias.consultas, 1);

      // Lo que habría otorgado el trigger al acreditar la XP del cierre.
      insignias.catalogo = [
        Insignia(
          id: _diezMil.id,
          nombre: _diezMil.nombre,
          descripcion: _diezMil.descripcion,
          icono: _diezMil.icono,
          xpRequerida: _diezMil.xpRequerida,
          obtenidaEl: DateTime.utc(2026, 9, 29, 7),
        ),
      ];
      expect(await finalizar(), isNull);

      final despues = await container.read(insigniasProvider.future);
      expect(insignias.consultas, 2);
      expect(despues.single.obtenida, isTrue);
    });

    test(
      'si el cierre no se guardó, no hay insignias nuevas que leer',
      () async {
        await container.read(insigniasProvider.future);
        entrenamientos.fallar = true;

        expect(await finalizar(), isNotNull);

        await container.read(insigniasProvider.future);
        expect(insignias.consultas, 1);
      },
    );
  });
}

const _diezMil = Insignia(
  id: 'i-3',
  nombre: 'Diez mil',
  descripcion: 'Tus primeros 10 km en una salida',
  icono: 'diez',
  xpRequerida: 105,
);

class _EntrenamientosFalso implements EntrenamientoRepository {
  bool fallar = false;

  @override
  Future<void> finalizar({
    required String entrenamientoId,
    required DateTime fechaFin,
    required Duration duracion,
    double? distanciaMetros,
  }) async {
    if (fallar) throw StateError('Supabase no disponible');
  }

  @override
  Future<String> crear({required String tipoActividadId}) =>
      throw UnimplementedError();

  @override
  Future<void> cancelar({
    required String entrenamientoId,
    required DateTime fechaFin,
  }) => throw UnimplementedError();

  @override
  Future<ResumenEntrenamiento?> cargarFinalizado(String entrenamientoId) =>
      throw UnimplementedError();
}
