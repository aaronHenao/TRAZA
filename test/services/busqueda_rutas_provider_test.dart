import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/services/busqueda_rutas_provider.dart';
import 'package:traza/services/rutas_service.dart';
import 'package:traza/services/ubicacion_provider.dart';
import 'package:traza/services/zonas_service.dart';

import '../utiles/buscador_de_zonas_falso.dart';
import '../utiles/fuente_ubicacion_falsa.dart';
import '../utiles/rutas_repository_falso.dart';

/// Pruebas de la búsqueda de Explorar rutas (SCRUM-254): qué se busca a
/// partir de lo escrito, cuándo sale la consulta y con qué.
///
/// Las de la espera corren como pruebas de widget para manejar el reloj
/// con `pump`, como las del foro con su espera de cambios.
void main() {
  group('lo que se busca a partir de lo escrito', () {
    test('sin espacios en los extremos y con los de en medio juntos', () {
      expect(terminoDeBusqueda('  parque   norte  '), 'parque norte');
    });

    test('con menos de dos letras no hay búsqueda', () {
      expect(terminoDeBusqueda(''), isNull);
      expect(terminoDeBusqueda('a'), isNull);
      expect(terminoDeBusqueda('   a   '), isNull);
    });

    test('con dos ya hay', () {
      expect(terminoDeBusqueda('ab'), 'ab');
    });
  });

  group('la consulta', () {
    final nutibara = rutaDePrueba(
      id: 'r-1',
      nombre: 'Subida al Nutibara',
      estado: EstadoRuta.publicada,
    );

    late RutasRepositorioFalso repositorio;
    late BuscadorDeZonasFalso zonas;

    setUp(() {
      repositorio = RutasRepositorioFalso(rutas: [nutibara]);
      zonas = BuscadorDeZonasFalso(zonas: {'envigado': envigado});
    });

    /// Un contenedor con la búsqueda viva, como la tiene la pantalla.
    ProviderContainer crear({
      UbicacionUsuario ubicacion = const UbicacionSinPermiso(),
    }) {
      final contenedor = ProviderContainer(
        overrides: [
          rutasRepositoryProvider.overrideWithValue(repositorio),
          ubicacionActualProvider.overrideWith((ref) async => ubicacion),
          buscadorDeZonasProvider.overrideWithValue(zonas),
        ],
      );
      addTearDown(contenedor.dispose);
      // Lo que tiene vivo la pantalla: la barra, su confirmación, y la lista
      // con la zona encontrada.
      contenedor
        ..listen(busquedaConfirmadaProvider, (_, _) {})
        ..listen(busquedaRutasProvider, (_, _) {})
        ..listen(zonaBuscadaProvider, (_, _) {});
      return contenedor;
    }

    void escribir(ProviderContainer contenedor, String texto) =>
        contenedor.read(textoBusquedaRutasProvider.notifier).state = texto;

    testWidgets('sin nada escrito no consulta', (tester) async {
      final contenedor = crear();

      await tester.pump(esperaBusquedaRutas);

      expect(contenedor.read(busquedaRutasProvider).valueOrNull, isNull);
      expect(repositorio.busquedas, isEmpty);
    });

    testWidgets('espera a que el usuario deje de escribir: sale una sola '
        'consulta, con lo último', (tester) async {
      final contenedor = crear();

      for (final texto in ['nu', 'nut', 'nutib', 'nutibara']) {
        escribir(contenedor, texto);
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(repositorio.busquedas, isEmpty);

      await tester.pump(esperaBusquedaRutas);

      expect([for (final b in repositorio.busquedas) b.termino], ['nutibara']);
      expect(contenedor.read(busquedaRutasProvider).valueOrNull, [nutibara]);
    });

    testWidgets('si borra antes de que se cumpla la espera, no consulta', (
      tester,
    ) async {
      final contenedor = crear();

      escribir(contenedor, 'nutibara');
      await tester.pump(const Duration(milliseconds: 100));
      escribir(contenedor, '');
      await tester.pump(esperaBusquedaRutas);

      expect(repositorio.busquedas, isEmpty);
      expect(contenedor.read(busquedaRutasProvider).valueOrNull, isNull);
    });

    testWidgets('un espacio de más al final no repite la búsqueda', (
      tester,
    ) async {
      final contenedor = crear();

      escribir(contenedor, 'nutibara');
      await tester.pump(esperaBusquedaRutas);
      escribir(contenedor, 'nutibara ');
      await tester.pump(esperaBusquedaRutas);

      expect(repositorio.busquedas, hasLength(1));
    });

    testWidgets('con la ubicación conocida la manda, para ordenar por '
        'cercanía', (tester) async {
      final enLaU = puntoDePrueba(latitud: 6.2318, longitud: -75.6105);
      final contenedor = crear(ubicacion: UbicacionConocida(enLaU));

      escribir(contenedor, 'nutibara');
      // La ubicación tiene que llegar antes de que se cumpla la espera.
      await tester.pump();
      await tester.pump(esperaBusquedaRutas);

      final busqueda = repositorio.busquedas.last;
      expect(busqueda.latitud, enLaU.latitud);
      expect(busqueda.longitud, enLaU.longitud);
    });

    testWidgets('sin la ubicación busca igual, sin coordenadas', (
      tester,
    ) async {
      final contenedor = crear(ubicacion: const UbicacionApagada());

      escribir(contenedor, 'nutibara');
      await tester.pump();
      await tester.pump(esperaBusquedaRutas);

      final busqueda = repositorio.busquedas.single;
      expect(busqueda.latitud, isNull);
      expect(busqueda.longitud, isNull);
      expect(contenedor.read(busquedaRutasProvider).valueOrNull, [nutibara]);
    });

    testWidgets('si falla, el error llega a la pantalla', (tester) async {
      repositorio.errorBusqueda = StateError('sin red');
      final contenedor = crear();

      escribir(contenedor, 'nutibara');
      await tester.pump(esperaBusquedaRutas);
      await tester.pump();

      expect(contenedor.read(busquedaRutasProvider).error, isA<StateError>());
    });

    group('la zona (SCRUM-255)', () {
      /// Lo que hace la tecla de buscar.
      void confirmar(ProviderContainer contenedor, String texto) =>
          contenedor.read(busquedaConfirmadaProvider.notifier).state =
              terminoDeBusqueda(texto);

      testWidgets('mientras se escribe no pregunta por ningún lugar', (
        tester,
      ) async {
        final contenedor = crear();

        escribir(contenedor, 'envigado');
        await tester.pump(esperaBusquedaRutas);

        expect(zonas.consultas, isEmpty);
        expect(repositorio.busquedas.single.zona, isNull);
        expect(contenedor.read(zonaBuscadaProvider).valueOrNull, isNull);
      });

      testWidgets('al confirmar pregunta por el lugar y busca enseguida, '
          'con su zona', (tester) async {
        final contenedor = crear();

        escribir(contenedor, 'envigado');
        confirmar(contenedor, 'envigado');
        // Sin la espera de cuando se escribe.
        await tester.pump(Duration.zero);

        expect([for (final c in zonas.consultas) c.texto], ['envigado']);
        expect(repositorio.busquedas.single.zona, envigado);
        expect(contenedor.read(zonaBuscadaProvider).valueOrNull, envigado);

        // La búsqueda de antes de confirmar se abandonó sin consultar.
        await tester.pump(esperaBusquedaRutas);
        expect(repositorio.busquedas, hasLength(1));
      });

      testWidgets('si vuelve a escribir, lo confirmado ya no vale: busca sin '
          'zona', (tester) async {
        final contenedor = crear();
        escribir(contenedor, 'envigado');
        confirmar(contenedor, 'envigado');
        await tester.pump(Duration.zero);

        escribir(contenedor, 'envigad');
        await tester.pump(esperaBusquedaRutas);
        await tester.pump(Duration.zero);

        expect(repositorio.busquedas.last.termino, 'envigad');
        expect(repositorio.busquedas.last.zona, isNull);
        expect(zonas.consultas, hasLength(1));
      });

      testWidgets('con la ubicación del usuario la pasa, para preferir los '
          'lugares cercanos', (tester) async {
        final enLaU = puntoDePrueba(latitud: 6.2318, longitud: -75.6105);
        final contenedor = crear(ubicacion: UbicacionConocida(enLaU));

        escribir(contenedor, 'envigado');
        // La ubicación llega antes de confirmar.
        await tester.pump(Duration.zero);
        confirmar(contenedor, 'envigado');
        await tester.pump(Duration.zero);

        final consulta = zonas.consultas.single;
        expect(consulta.latitud, enLaU.latitud);
        expect(consulta.longitud, enLaU.longitud);
        await tester.pump(esperaBusquedaRutas);
      });

      testWidgets('si lo escrito no es un lugar, busca solo por nombre y '
          'creador', (tester) async {
        final contenedor = crear();

        escribir(contenedor, 'nutibara');
        confirmar(contenedor, 'nutibara');
        await tester.pump(Duration.zero);

        expect(zonas.consultas.single.texto, 'nutibara');
        expect(repositorio.busquedas.single.zona, isNull);
        expect(contenedor.read(busquedaRutasProvider).valueOrNull, [nutibara]);
        await tester.pump(esperaBusquedaRutas);
      });

      testWidgets('si no se pudo preguntar por el lugar, busca igual por '
          'nombre y creador, y el error queda para la pantalla', (
        tester,
      ) async {
        zonas.error = const ZonaNoDisponibleException('sin conexión');
        final contenedor = crear();

        escribir(contenedor, 'nutibara');
        confirmar(contenedor, 'nutibara');
        await tester.pump(Duration.zero);

        expect(repositorio.busquedas.single.zona, isNull);
        expect(contenedor.read(busquedaRutasProvider).valueOrNull, [nutibara]);
        expect(
          contenedor.read(zonaBuscadaProvider).error,
          isA<ZonaNoDisponibleException>(),
        );
        await tester.pump(esperaBusquedaRutas);
      });
    });
  });
}
