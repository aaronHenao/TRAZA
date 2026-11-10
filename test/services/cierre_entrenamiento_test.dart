import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/insignia.dart';
import 'package:traza/models/nivel.dart';
import 'package:traza/models/recorrido.dart';
import 'package:traza/models/resumen_entrenamiento.dart';
import 'package:traza/models/reto_del_usuario.dart';
import 'package:traza/models/ruta.dart';
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
import 'package:traza/services/retos_provider.dart';
import 'package:traza/services/retos_service.dart';
import 'package:traza/services/rutas_oficiales_service.dart';

import '../utiles/experiencia_falsa.dart';
import '../utiles/insignias_falsas.dart';
import '../utiles/niveles_falso.dart';
import '../utiles/reloj_falso.dart';
import '../utiles/retos_repository_falso.dart';
import '../utiles/rutas_oficiales_repository_falso.dart';
import '../utiles/rutas_repository_falso.dart';

/// Pruebas de la XP en el cierre del entrenamiento (SCRUM-206).
///
/// La XP la asigna el trigger de la base en el mismo cierre; lo que le toca a
/// la app es volver a leer la acumulada para que la progresión la refleje.
///
/// En rutas oficiales, etapa 3, el cierre también suelta la ruta que se
/// estaba corriendo, salvo que no se haya podido guardar.
void main() {
  late _EntrenamientosFalso entrenamientos;
  late ExperienciaFalsa experiencia;
  late InsigniasFalsas insignias;
  late _RetosContados retos;
  late RutasOficialesRepositorioFalso rutasOficiales;
  late ProviderContainer container;

  setUp(() {
    entrenamientos = _EntrenamientosFalso();
    experiencia = ExperienciaFalsa(acumulada: 100);
    insignias = InsigniasFalsas(catalogo: const [_diezMil]);
    retos = _RetosContados();
    // El camino del mapa de progresión (rutas oficiales, etapa 2). Solo lo
    // lee el grupo del mapa, que es el único que lo mantiene vivo.
    rutasOficiales = RutasOficialesRepositorioFalso(
      oficiales: [
        rutaDePrueba(
          id: 'ruta-estadio',
          nombre: 'Vuelta al estadio',
          estado: EstadoRuta.publicada,
        ),
        rutaDePrueba(
          id: 'ruta-nutibara',
          nombre: 'Cerro Nutibara',
          estado: EstadoRuta.publicada,
        ),
      ],
    );

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
        retosRepositoryProvider.overrideWithValue(retos),
        rutasOficialesRepositoryProvider.overrideWithValue(rutasOficiales),
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

  test('con el mapa cerrado, cerrar no lo consulta: se lee al entrar a su '
      'pestaña', () async {
    expect(await finalizar(), isNull);

    expect(rutasOficiales.consultas, 0);
    expect(rutasOficiales.consultasCompletadas, 0);
  });

  group('mapa de progresión (rutas oficiales, etapa 2): la invalidación al '
      'cerrar se conserva', () {
    setUp(() {
      // Como el mapa abierto en su pestaña: lo mantiene vivo. Va solo en este
      // grupo para no alterar las consultas que cuentan las pruebas de arriba.
      container.listen(mapaProgresionProvider, (_, _) {});
    });

    test('al finalizar, el mapa vuelve a consultar las rutas completadas y '
        'el marcador avanza', () async {
      final antes = await container.read(mapaProgresionProvider.future);
      expect(antes.totalCompletadas, 0);
      expect(antes.siguiente?.ruta.id, 'ruta-estadio');
      expect(rutasOficiales.consultasCompletadas, 1);

      // Lo que en la etapa 4 hará el cierre: dejar la ruta en
      // `rutas_completadas`.
      rutasOficiales.completadasPorMi.add('ruta-estadio');
      expect(await finalizar(), isNull);

      final despues = await container.read(mapaProgresionProvider.future);
      expect(rutasOficiales.consultasCompletadas, 2);
      expect(despues.totalCompletadas, 1);
      expect(despues.indiceActual, 1);
      expect(despues.siguiente?.ruta.id, 'ruta-nutibara');
    });

    test(
      'si el cierre no se guardó, el mapa no se vuelve a consultar',
      () async {
        final antes = await container.read(mapaProgresionProvider.future);
        expect(antes.totalCompletadas, 0);
        entrenamientos.fallar = true;

        // Aunque la base cambiara, sin cierre no hay motivo para releer.
        rutasOficiales.completadasPorMi.add('ruta-estadio');
        expect(await finalizar(), isNotNull);

        final despues = await container.read(mapaProgresionProvider.future);
        expect(rutasOficiales.consultasCompletadas, 1);
        expect(rutasOficiales.consultas, 1);
        expect(despues.totalCompletadas, 0);
        expect(despues.indiceActual, 0);
      },
    );

    test('el mapa ya no lee la XP: la XP sigue en Tu progresión', () async {
      await container.read(mapaProgresionProvider.future);
      await container.read(progresionProvider.future);

      // La única lectura es la de Tu progresión, que el setUp mantiene viva.
      expect(experiencia.consultas, 1);
    });
  });

  group('ruta en curso (rutas oficiales, etapa 3)', () {
    final estadio = rutaDePrueba(
      id: 'ruta-estadio',
      nombre: 'Vuelta al estadio',
      estado: EstadoRuta.publicada,
    );

    Ruta? rutaEnCurso() => container.read(rutaEnCursoProvider);

    setUp(() => container.read(rutaEnCursoProvider.notifier).fijar(estadio));

    test('al finalizar con éxito, la ruta en curso vuelve a null', () async {
      expect(rutaEnCurso()?.id, 'ruta-estadio');

      expect(await finalizar(), isNull);

      expect(rutaEnCurso(), isNull);
    });

    test(
      'si el cierre falla, la ruta en curso se conserva para reintentar',
      () async {
        entrenamientos.fallar = true;

        expect(await finalizar(), isNotNull);

        expect(rutaEnCurso()?.id, 'ruta-estadio');
      },
    );

    test(
      'si los puntos no se guardaron, la ruta en curso se conserva',
      () async {
        final error = await container
            .read(cierreEntrenamientoProvider)
            .finalizar(
              duracion: const Duration(minutes: 30),
              recorrido: const Recorrido(
                sincronizacion: EstadoSincronizacion.fallida,
              ),
            );

        expect(error, isNotNull);
        expect(rutaEnCurso()?.id, 'ruta-estadio');
      },
    );
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

  group('retos del usuario', () {
    test(
      'si estaban en memoria, se vuelven a leer con el progreso nuevo',
      () async {
        // Como el resumen o la pantalla de retos abiertos: los mantiene vivos.
        container.listen(misRetosProvider, (_, _) {});
        await container.read(misRetosProvider.future);
        expect(retos.consultas, 1);

        expect(await finalizar(), isNull);

        await container.read(misRetosProvider.future);
        expect(retos.consultas, 2);
      },
    );

    test('si nadie los tenía, no se consultan al cerrar', () async {
      expect(await finalizar(), isNull);

      expect(retos.consultas, 0);
    });
  });
}

class _RetosContados extends RetosRepositorioFalso {
  var consultas = 0;

  @override
  Future<List<RetoDelUsuario>> misRetos() async {
    consultas++;
    return const [];
  }
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
  Future<String> crear({required String tipoActividadId, String? rutaId}) =>
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
