import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/services/busqueda_rutas_provider.dart';
import 'package:traza/services/rutas_service.dart';
import 'package:traza/services/ubicacion_provider.dart';

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

    setUp(() => repositorio = RutasRepositorioFalso(rutas: [nutibara]));

    /// Un contenedor con la búsqueda viva, como la tiene la pantalla.
    ProviderContainer crear({
      UbicacionUsuario ubicacion = const UbicacionSinPermiso(),
    }) {
      final contenedor = ProviderContainer(
        overrides: [
          rutasRepositoryProvider.overrideWithValue(repositorio),
          ubicacionActualProvider.overrideWith((ref) async => ubicacion),
        ],
      );
      addTearDown(contenedor.dispose);
      contenedor.listen(busquedaRutasProvider, (_, _) {});
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
  });
}
