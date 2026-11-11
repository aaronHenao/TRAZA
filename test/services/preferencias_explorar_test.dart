import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:traza/models/dificultad.dart';
import 'package:traza/models/rango_distancia.dart';
import 'package:traza/services/preferencias_explorar.dart';

/// Dónde se guardan los filtros de Explorar rutas (preferencias de Explorar,
/// Desarrollo Móvil).
///
/// La del teléfono se prueba con SharedPreferences de verdad, en memoria: lo
/// que importa aquí es justo cómo quedan guardados (claves y valores), así
/// que un doble no serviría de nada.
void main() {
  group('en el teléfono, con SharedPreferences', () {
    /// Las preferencias con [guardado] ya en el teléfono, como al abrir la
    /// app.
    Future<PreferenciasExplorarCompartidas> abrir([
      Map<String, Object> guardado = const {},
    ]) async {
      SharedPreferences.setMockInitialValues(guardado);
      return PreferenciasExplorarCompartidas(
        await SharedPreferences.getInstance(),
      );
    }

    /// Lo que queda en el teléfono al cerrar la app y abrirla de nuevo: otra
    /// instancia que lee lo guardado, no la que la app tenía en memoria.
    Future<SharedPreferences> reabrirLaApp() async {
      SharedPreferences.resetStatic();
      return SharedPreferences.getInstance();
    }

    test(
      'cargar() es lo que usa main: trae lo guardado en el teléfono',
      () async {
        SharedPreferences.resetStatic();
        SharedPreferences.setMockInitialValues({
          PreferenciasExplorarCompartidas.claveDificultad: 'facil',
          PreferenciasExplorarCompartidas.claveDistancia: 'de5a10',
        });

        final preferencias = await PreferenciasExplorarCompartidas.cargar();

        expect(preferencias.dificultad(), Dificultad.facil);
        expect(preferencias.distancia(), RangoDistancia.de5a10);
      },
    );

    test('guarda la dificultad en «explorar.dificultad» y el rango en '
        '«explorar.distancia»', () {
      expect(
        PreferenciasExplorarCompartidas.claveDificultad,
        'explorar.dificultad',
      );
      expect(
        PreferenciasExplorarCompartidas.claveDistancia,
        'explorar.distancia',
      );
    });

    test('sin nada guardado, no hay dificultad ni rango', () async {
      final preferencias = await abrir();

      expect(preferencias.dificultad(), isNull);
      expect(preferencias.distancia(), isNull);
    });

    test('lee la dificultad guardada por su valor de la base', () async {
      for (final (guardado, dificultad) in [
        ('facil', Dificultad.facil),
        ('moderada', Dificultad.moderada),
        ('dificil', Dificultad.dificil),
      ]) {
        final preferencias = await abrir({'explorar.dificultad': guardado});

        expect(preferencias.dificultad(), dificultad, reason: guardado);
        expect(preferencias.distancia(), isNull, reason: guardado);
      }
    });

    test('lee el rango guardado por su nombre', () async {
      for (final (guardado, rango) in [
        ('menosDe5', RangoDistancia.menosDe5),
        ('de5a10', RangoDistancia.de5a10),
        ('de10a20', RangoDistancia.de10a20),
        ('masDe20', RangoDistancia.masDe20),
      ]) {
        final preferencias = await abrir({'explorar.distancia': guardado});

        expect(preferencias.distancia(), rango, reason: guardado);
        expect(preferencias.dificultad(), isNull, reason: guardado);
      }
    });

    test('lee los dos a la vez', () async {
      final preferencias = await abrir({
        'explorar.dificultad': 'facil',
        'explorar.distancia': 'de5a10',
      });

      expect(preferencias.dificultad(), Dificultad.facil);
      expect(preferencias.distancia(), RangoDistancia.de5a10);
    });

    test('elegir una dificultad la deja en el teléfono con su valor de la '
        'base, y sigue ahí al abrir la app de nuevo (criterio 1)', () async {
      final preferencias = await abrir();

      await preferencias.guardarDificultad(Dificultad.moderada);

      expect(preferencias.dificultad(), Dificultad.moderada);
      final telefono = await reabrirLaApp();
      expect(telefono.getString('explorar.dificultad'), 'moderada');
      expect(
        PreferenciasExplorarCompartidas(telefono).dificultad(),
        Dificultad.moderada,
      );
    });

    test('cada dificultad se guarda con su valor de la base', () async {
      for (final dificultad in Dificultad.values) {
        final preferencias = await abrir();

        await preferencias.guardarDificultad(dificultad);

        final telefono = await reabrirLaApp();
        expect(
          telefono.getString('explorar.dificultad'),
          dificultad.valorDb,
          reason: dificultad.name,
        );
      }
    });

    test('elegir un rango lo deja en el teléfono con su nombre, y sigue ahí '
        'al abrir la app de nuevo (criterio 1)', () async {
      final preferencias = await abrir();

      await preferencias.guardarDistancia(RangoDistancia.de10a20);

      expect(preferencias.distancia(), RangoDistancia.de10a20);
      final telefono = await reabrirLaApp();
      expect(telefono.getString('explorar.distancia'), 'de10a20');
      expect(
        PreferenciasExplorarCompartidas(telefono).distancia(),
        RangoDistancia.de10a20,
      );
    });

    test('cada rango se guarda con su nombre', () async {
      for (final rango in RangoDistancia.values) {
        final preferencias = await abrir();

        await preferencias.guardarDistancia(rango);

        final telefono = await reabrirLaApp();
        expect(
          telefono.getString('explorar.distancia'),
          rango.name,
          reason: rango.name,
        );
      }
    });

    test('elegir otro reemplaza al guardado', () async {
      final preferencias = await abrir({
        'explorar.dificultad': 'facil',
        'explorar.distancia': 'menosDe5',
      });

      await preferencias.guardarDificultad(Dificultad.dificil);
      await preferencias.guardarDistancia(RangoDistancia.masDe20);

      final telefono = await reabrirLaApp();
      expect(telefono.getString('explorar.dificultad'), 'dificil');
      expect(telefono.getString('explorar.distancia'), 'masDe20');
    });

    test('quitar la dificultad borra su clave, y el rango sigue guardado '
        '(criterio 3)', () async {
      final preferencias = await abrir({
        'explorar.dificultad': 'facil',
        'explorar.distancia': 'de5a10',
      });

      await preferencias.guardarDificultad(null);

      expect(preferencias.dificultad(), isNull);
      final telefono = await reabrirLaApp();
      expect(telefono.containsKey('explorar.dificultad'), isFalse);
      expect(telefono.getString('explorar.distancia'), 'de5a10');
    });

    test('quitar el rango borra su clave, y la dificultad sigue guardada '
        '(criterio 3)', () async {
      final preferencias = await abrir({
        'explorar.dificultad': 'facil',
        'explorar.distancia': 'de5a10',
      });

      await preferencias.guardarDistancia(null);

      expect(preferencias.distancia(), isNull);
      final telefono = await reabrirLaApp();
      expect(telefono.containsKey('explorar.distancia'), isFalse);
      expect(telefono.getString('explorar.dificultad'), 'facil');
    });

    test('quitar lo que no estaba guardado no falla', () async {
      final preferencias = await abrir();

      await preferencias.guardarDificultad(null);
      await preferencias.guardarDistancia(null);

      final telefono = await reabrirLaApp();
      expect(telefono.containsKey('explorar.dificultad'), isFalse);
      expect(telefono.containsKey('explorar.distancia'), isFalse);
    });

    test('una dificultad que no se reconoce se lee como ninguna '
        '(criterio 4)', () async {
      // La etiqueta, otra mayúscula, un nivel que no existe o nada.
      for (final guardado in ['extrema', 'Fácil', 'FACIL', '']) {
        final preferencias = await abrir({'explorar.dificultad': guardado});

        expect(preferencias.dificultad(), isNull, reason: guardado);
      }
    });

    test('un rango que no se reconoce se lee como ninguno '
        '(criterio 4)', () async {
      // Un rango que no existe, la etiqueta del chip, otra mayúscula, su
      // posición o nada.
      for (final guardado in ['de20a40', '5 a 10 km', 'De5a10', '1', '']) {
        final preferencias = await abrir({'explorar.distancia': guardado});

        expect(preferencias.distancia(), isNull, reason: guardado);
      }
    });

    test('un valor de otro tipo se lee como ninguno, sin fallar '
        '(criterio 4)', () async {
      for (final guardado in <Object>[
        1,
        true,
        2.5,
        <String>['facil'],
      ]) {
        final preferencias = await abrir({
          'explorar.dificultad': guardado,
          'explorar.distancia': guardado,
        });

        expect(preferencias.dificultad(), isNull, reason: '$guardado');
        expect(preferencias.distancia(), isNull, reason: '$guardado');
      }
    });

    test('lo que no se reconoce en una clave no afecta a la otra '
        '(criterio 4)', () async {
      final soloLaDificultad = await abrir({
        'explorar.dificultad': 'facil',
        'explorar.distancia': 42,
      });
      expect(soloLaDificultad.dificultad(), Dificultad.facil);
      expect(soloLaDificultad.distancia(), isNull);

      final soloElRango = await abrir({
        'explorar.dificultad': 'extrema',
        'explorar.distancia': 'de5a10',
      });
      expect(soloElRango.dificultad(), isNull);
      expect(soloElRango.distancia(), RangoDistancia.de5a10);
    });

    test('elegir sobre un valor que no se reconocía lo reemplaza', () async {
      final preferencias = await abrir({
        'explorar.dificultad': 7,
        'explorar.distancia': 'de20a40',
      });

      await preferencias.guardarDificultad(Dificultad.facil);
      await preferencias.guardarDistancia(RangoDistancia.de5a10);

      final telefono = await reabrirLaApp();
      expect(telefono.getString('explorar.dificultad'), 'facil');
      expect(telefono.getString('explorar.distancia'), 'de5a10');
    });
  });

  group('en memoria, sin el teléfono', () {
    test('empieza sin dificultad ni rango', () {
      final preferencias = PreferenciasExplorarEnMemoria();

      expect(preferencias.dificultad(), isNull);
      expect(preferencias.distancia(), isNull);
    });

    test('devuelve lo último que se guardó', () async {
      final preferencias = PreferenciasExplorarEnMemoria();

      await preferencias.guardarDificultad(Dificultad.facil);
      await preferencias.guardarDistancia(RangoDistancia.menosDe5);
      await preferencias.guardarDificultad(Dificultad.moderada);

      expect(preferencias.dificultad(), Dificultad.moderada);
      expect(preferencias.distancia(), RangoDistancia.menosDe5);
    });

    test('guardar null lo borra, y el otro sigue', () async {
      final preferencias = PreferenciasExplorarEnMemoria();
      await preferencias.guardarDificultad(Dificultad.dificil);
      await preferencias.guardarDistancia(RangoDistancia.de10a20);

      await preferencias.guardarDificultad(null);

      expect(preferencias.dificultad(), isNull);
      expect(preferencias.distancia(), RangoDistancia.de10a20);

      await preferencias.guardarDistancia(null);

      expect(preferencias.distancia(), isNull);
    });

    test('cada una guarda lo suyo: lo de una no aparece en otra', () async {
      final una = PreferenciasExplorarEnMemoria();
      await una.guardarDificultad(Dificultad.facil);
      await una.guardarDistancia(RangoDistancia.masDe20);

      final otra = PreferenciasExplorarEnMemoria();

      expect(otra.dificultad(), isNull);
      expect(otra.distancia(), isNull);
    });
  });
}
