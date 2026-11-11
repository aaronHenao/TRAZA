import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:traza/models/dificultad.dart';
import 'package:traza/models/filtros_rutas.dart';
import 'package:traza/models/rango_distancia.dart';
import 'package:traza/services/filtros_rutas_provider.dart';
import 'package:traza/services/preferencias_explorar.dart';

import '../utiles/preferencias_explorar_falsa.dart';

/// Pruebas de lo elegido para filtrar en Explorar rutas (SCRUM-273 a
/// SCRUM-275).
void main() {
  late ProviderContainer contenedor;

  setUp(() {
    contenedor = ProviderContainer();
    // Como la pantalla: mientras alguien escucha, lo elegido no se borra.
    contenedor.listen(filtrosRutasProvider, (_, _) {});
  });

  tearDown(() => contenedor.dispose());

  test('empieza sin nada elegido', () {
    expect(contenedor.read(filtrosRutasProvider), const FiltrosRutas());
  });

  test('junta la dificultad y la distancia elegidas', () {
    contenedor.read(dificultadRutasProvider.notifier).state =
        Dificultad.moderada;
    contenedor.read(rangoDistanciaProvider.notifier).state =
        RangoDistancia.de10a20;

    expect(
      contenedor.read(filtrosRutasProvider),
      const FiltrosRutas(
        dificultad: Dificultad.moderada,
        distancia: RangoDistancia.de10a20,
      ),
    );
  });

  test('quitar uno deja el otro', () {
    contenedor.read(dificultadRutasProvider.notifier).state = Dificultad.facil;
    contenedor.read(rangoDistanciaProvider.notifier).state =
        RangoDistancia.menosDe5;

    contenedor.read(rangoDistanciaProvider.notifier).state = null;

    expect(
      contenedor.read(filtrosRutasProvider),
      const FiltrosRutas(dificultad: Dificultad.facil),
    );
  });

  test('sin preferencias del teléfono usa unas en memoria, y empieza sin '
      'nada elegido, como antes (criterio 5)', () {
    expect(
      contenedor.read(preferenciasExplorarProvider),
      isA<PreferenciasExplorarEnMemoria>(),
    );
    expect(contenedor.read(filtrosRutasProvider), const FiltrosRutas());
  });

  group('guardados en el teléfono (preferencias de Explorar, Desarrollo '
      'Móvil)', () {
    /// Explorar con [preferencias] en lugar de las del teléfono, y alguien
    /// escuchando los filtros, como la pantalla.
    ProviderContainer abrirExplorar(PreferenciasExplorar preferencias) {
      final explorar = ProviderContainer(
        overrides: [
          preferenciasExplorarProvider.overrideWithValue(preferencias),
        ],
      );
      addTearDown(explorar.dispose);
      explorar.listen(filtrosRutasProvider, (_, _) {});
      return explorar;
    }

    test('empieza con la dificultad y el rango guardados (criterio 2)', () {
      final explorar = abrirExplorar(
        PreferenciasExplorarFalsa(
          dificultadGuardada: Dificultad.facil,
          distanciaGuardada: RangoDistancia.de5a10,
        ),
      );

      expect(explorar.read(dificultadRutasProvider), Dificultad.facil);
      expect(explorar.read(rangoDistanciaProvider), RangoDistancia.de5a10);
      expect(
        explorar.read(filtrosRutasProvider),
        const FiltrosRutas(
          dificultad: Dificultad.facil,
          distancia: RangoDistancia.de5a10,
        ),
      );
    });

    test('con solo el rango guardado, la dificultad empieza en «Todas»', () {
      final explorar = abrirExplorar(
        PreferenciasExplorarFalsa(distanciaGuardada: RangoDistancia.masDe20),
      );

      expect(
        explorar.read(filtrosRutasProvider),
        const FiltrosRutas(distancia: RangoDistancia.masDe20),
      );
    });

    test('abrir Explorar no borra ni cambia lo guardado', () async {
      final preferencias = PreferenciasExplorarFalsa(
        dificultadGuardada: Dificultad.moderada,
        distanciaGuardada: RangoDistancia.de10a20,
      );

      abrirExplorar(preferencias);
      await Future<void>.delayed(Duration.zero);

      expect(preferencias.dificultadGuardada, Dificultad.moderada);
      expect(preferencias.distanciaGuardada, RangoDistancia.de10a20);
      // Ni siquiera vuelve a escribir lo mismo: abrir no es elegir.
      expect(preferencias.dificultadesGuardadas, isEmpty);
      expect(preferencias.distanciasGuardadas, isEmpty);
    });

    test('elegir una dificultad la guarda en el teléfono, sin tocar el rango '
        'guardado (criterio 1)', () async {
      final preferencias = PreferenciasExplorarFalsa(
        distanciaGuardada: RangoDistancia.de10a20,
      );
      final explorar = abrirExplorar(preferencias);

      explorar.read(dificultadRutasProvider.notifier).state =
          Dificultad.moderada;
      await Future<void>.delayed(Duration.zero);

      expect(preferencias.dificultadGuardada, Dificultad.moderada);
      expect(preferencias.dificultadesGuardadas.last, Dificultad.moderada);
      expect(preferencias.distanciaGuardada, RangoDistancia.de10a20);
    });

    test('elegir un rango lo guarda en el teléfono, sin tocar la dificultad '
        'guardada (criterio 1)', () async {
      final preferencias = PreferenciasExplorarFalsa(
        dificultadGuardada: Dificultad.facil,
      );
      final explorar = abrirExplorar(preferencias);

      explorar.read(rangoDistanciaProvider.notifier).state =
          RangoDistancia.menosDe5;
      await Future<void>.delayed(Duration.zero);

      expect(preferencias.distanciaGuardada, RangoDistancia.menosDe5);
      expect(preferencias.distanciasGuardadas.last, RangoDistancia.menosDe5);
      expect(preferencias.dificultadGuardada, Dificultad.facil);
    });

    test('cada cambio se guarda, y queda el último (criterio 1)', () async {
      final preferencias = PreferenciasExplorarFalsa();
      final explorar = abrirExplorar(preferencias);

      explorar.read(dificultadRutasProvider.notifier).state = Dificultad.facil;
      explorar.read(rangoDistanciaProvider.notifier).state =
          RangoDistancia.de5a10;
      await Future<void>.delayed(Duration.zero);
      expect(preferencias.dificultadGuardada, Dificultad.facil);
      expect(preferencias.distanciaGuardada, RangoDistancia.de5a10);

      explorar.read(dificultadRutasProvider.notifier).state =
          Dificultad.dificil;
      explorar.read(rangoDistanciaProvider.notifier).state =
          RangoDistancia.masDe20;
      await Future<void>.delayed(Duration.zero);

      expect(preferencias.dificultadGuardada, Dificultad.dificil);
      expect(preferencias.distanciaGuardada, RangoDistancia.masDe20);
      expect(
        preferencias.dificultadesGuardadas,
        containsAllInOrder([Dificultad.facil, Dificultad.dificil]),
      );
      expect(
        preferencias.distanciasGuardadas,
        containsAllInOrder([RangoDistancia.de5a10, RangoDistancia.masDe20]),
      );
    });

    test('quitar la dificultad la borra de lo guardado (criterio 3)', () async {
      final preferencias = PreferenciasExplorarFalsa(
        dificultadGuardada: Dificultad.facil,
        distanciaGuardada: RangoDistancia.de5a10,
      );
      final explorar = abrirExplorar(preferencias);

      explorar.read(dificultadRutasProvider.notifier).state = null;
      await Future<void>.delayed(Duration.zero);

      expect(preferencias.dificultadGuardada, isNull);
      expect(preferencias.dificultadesGuardadas, isNotEmpty);
      expect(preferencias.dificultadesGuardadas.last, isNull);
      expect(preferencias.distanciaGuardada, RangoDistancia.de5a10);
    });

    test('quitar el rango lo borra de lo guardado (criterio 3)', () async {
      final preferencias = PreferenciasExplorarFalsa(
        dificultadGuardada: Dificultad.facil,
        distanciaGuardada: RangoDistancia.de5a10,
      );
      final explorar = abrirExplorar(preferencias);

      explorar.read(rangoDistanciaProvider.notifier).state = null;
      await Future<void>.delayed(Duration.zero);

      expect(preferencias.distanciaGuardada, isNull);
      expect(preferencias.distanciasGuardadas, isNotEmpty);
      expect(preferencias.distanciasGuardadas.last, isNull);
      expect(preferencias.dificultadGuardada, Dificultad.facil);
    });

    test('al volver a Explorar, los filtros se recrean con lo guardado '
        '(criterio 2)', () async {
      final explorar = ProviderContainer(
        overrides: [
          preferenciasExplorarProvider.overrideWithValue(
            PreferenciasExplorarFalsa(),
          ),
        ],
      );
      addTearDown(explorar.dispose);

      final pantalla = explorar.listen(filtrosRutasProvider, (_, _) {});
      explorar.read(dificultadRutasProvider.notifier).state =
          Dificultad.moderada;
      explorar.read(rangoDistanciaProvider.notifier).state =
          RangoDistancia.de10a20;
      await Future<void>.delayed(Duration.zero);

      // Sale de la sección: sin nadie que los escuche, se descartan.
      pantalla.close();
      await explorar.pump();
      expect(
        explorar.exists(dificultadRutasProvider),
        isFalse,
        reason: 'al salir de Explorar los filtros se descartan (autoDispose)',
      );
      expect(explorar.exists(rangoDistanciaProvider), isFalse);

      // Vuelve: se crean otra vez.
      explorar.listen(filtrosRutasProvider, (_, _) {});

      expect(
        explorar.read(filtrosRutasProvider),
        const FiltrosRutas(
          dificultad: Dificultad.moderada,
          distancia: RangoDistancia.de10a20,
        ),
      );
    });

    test('al abrir la app de nuevo, con las mismas preferencias, aparece lo '
        'elegido (criterio 2)', () async {
      final preferencias = PreferenciasExplorarFalsa();
      final antes = abrirExplorar(preferencias);
      antes.read(dificultadRutasProvider.notifier).state = Dificultad.dificil;
      antes.read(rangoDistanciaProvider.notifier).state =
          RangoDistancia.menosDe5;
      await Future<void>.delayed(Duration.zero);
      antes.dispose();

      final despues = abrirExplorar(preferencias);

      expect(
        despues.read(filtrosRutasProvider),
        const FiltrosRutas(
          dificultad: Dificultad.dificil,
          distancia: RangoDistancia.menosDe5,
        ),
      );
    });

    test('con las del teléfono de verdad, lo elegido sigue al abrir la app de '
        'nuevo (criterios 1 y 2)', () async {
      SharedPreferences.setMockInitialValues({});
      final antes = abrirExplorar(
        PreferenciasExplorarCompartidas(await SharedPreferences.getInstance()),
      );
      antes.read(dificultadRutasProvider.notifier).state = Dificultad.facil;
      antes.read(rangoDistanciaProvider.notifier).state = RangoDistancia.de5a10;
      await Future<void>.delayed(Duration.zero);
      antes.dispose();

      // Otra instancia, que lee lo que quedó en el teléfono.
      SharedPreferences.resetStatic();
      final despues = abrirExplorar(
        PreferenciasExplorarCompartidas(await SharedPreferences.getInstance()),
      );

      expect(
        despues.read(filtrosRutasProvider),
        const FiltrosRutas(
          dificultad: Dificultad.facil,
          distancia: RangoDistancia.de5a10,
        ),
      );
    });

    test('con lo guardado irreconocible, empieza sin filtros y nada falla '
        '(criterio 4)', () async {
      SharedPreferences.setMockInitialValues({
        'explorar.dificultad': 'extrema',
        'explorar.distancia': 42,
      });
      final explorar = abrirExplorar(
        PreferenciasExplorarCompartidas(await SharedPreferences.getInstance()),
      );

      expect(explorar.read(filtrosRutasProvider), const FiltrosRutas());
    });

    test('si solo uno es irreconocible, ese empieza vacío y el otro se aplica '
        '(criterio 4)', () async {
      SharedPreferences.setMockInitialValues({
        'explorar.dificultad': 'moderada',
        'explorar.distancia': 'de20a40',
      });
      final explorar = abrirExplorar(
        PreferenciasExplorarCompartidas(await SharedPreferences.getInstance()),
      );

      expect(
        explorar.read(filtrosRutasProvider),
        const FiltrosRutas(dificultad: Dificultad.moderada),
      );
    });

    test('si el teléfono no deja guardar, el filtro se aplica igual y nada '
        'falla', () async {
      final preferencias = PreferenciasExplorarFalsa()
        ..errorAlGuardar = Exception('sin espacio');
      final explorar = abrirExplorar(preferencias);

      explorar.read(dificultadRutasProvider.notifier).state = Dificultad.facil;
      explorar.read(rangoDistanciaProvider.notifier).state =
          RangoDistancia.de5a10;
      // Si el error de guardar quedara suelto, la prueba fallaría aquí.
      await Future<void>.delayed(Duration.zero);

      expect(preferencias.dificultadesGuardadas, contains(Dificultad.facil));
      expect(
        explorar.read(filtrosRutasProvider),
        const FiltrosRutas(
          dificultad: Dificultad.facil,
          distancia: RangoDistancia.de5a10,
        ),
      );
    });
  });
}
