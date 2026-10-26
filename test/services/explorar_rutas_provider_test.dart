import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:traza/models/estado_permisos.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/models/ruta_cercana.dart';
import 'package:traza/services/explorar_rutas_provider.dart';
import 'package:traza/services/permisos_provider.dart';
import 'package:traza/services/permisos_service.dart';
import 'package:traza/services/permisos_usuario_service.dart';
import 'package:traza/services/rutas_service.dart';
import 'package:traza/services/ubicacion_provider.dart';

import '../utiles/fuente_ubicacion_falsa.dart';
import '../utiles/rutas_repository_falso.dart';

class _MockPermisosService extends Mock implements PermisosService {}

/// Lo que la app guarda en `permisos_usuario`: aquí no interesa.
class _PermisosGuardadosFalso implements PermisosUsuarioRepository {
  @override
  Future<void> guardar(TipoPermiso tipo, {required bool concedido}) async {}
}

/// Pruebas de qué lista muestra Explorar rutas y en qué orden (SCRUM-246).
void main() {
  late _MockPermisosService permisos;
  late FuenteUbicacionFalsa fuente;
  late RutasRepositorioFalso repositorio;

  final vuelta = rutaDePrueba(
    id: 'r-1',
    nombre: 'Vuelta al estadio',
    estado: EstadoRuta.publicada,
    fechaPublicacion: DateTime(2026, 10, 18, 9),
  );
  final subida = rutaDePrueba(
    id: 'r-2',
    nombre: 'Subida al Nutibara',
    estado: EstadoRuta.publicada,
    fechaPublicacion: DateTime(2026, 10, 17, 9),
  );

  setUp(() {
    permisos = _MockPermisosService();
    fuente = FuenteUbicacionFalsa()
      ..puntoActual = puntoDePrueba(latitud: 6.2442, longitud: -75.5812);
    repositorio = RutasRepositorioFalso(rutas: [vuelta, subida]);
    when(
      () => permisos.estadoSalud(),
    ).thenAnswer((_) async => EstadoPermiso.desconocido);
  });

  tearDown(() => fuente.cerrar());

  Future<RutasParaExplorar> leer(EstadoPermiso ubicacion) async {
    when(() => permisos.estadoUbicacion()).thenAnswer((_) async => ubicacion);

    final container = ProviderContainer(
      overrides: [
        permisosServiceProvider.overrideWithValue(permisos),
        permisosUsuarioRepositoryProvider.overrideWithValue(
          _PermisosGuardadosFalso(),
        ),
        fuenteUbicacionProvider.overrideWithValue(fuente),
        rutasRepositoryProvider.overrideWithValue(repositorio),
      ],
    );
    addTearDown(container.dispose);

    // Como la app: primero se sabe qué decidió el usuario sobre la
    // ubicación, y después se pide la lista.
    await container.read(permisosProvider.notifier).actualizar();
    return container.read(rutasParaExplorarProvider.future);
  }

  group('sabiendo dónde está el usuario', () {
    test('ordena por cercanía desde su posición', () async {
      repositorio.rutasCercanas = [
        RutaCercana(ruta: subida, distanciaKm: 1.4),
        RutaCercana(ruta: vuelta, distanciaKm: 6.2),
      ];

      final explorar = await leer(EstadoPermiso.concedido);

      expect(explorar, isA<RutasPorCercania>());
      // El orden es el de la base, aunque la más reciente sea otra.
      expect([for (final r in explorar.rutas) r.id], ['r-2', 'r-1']);
      expect(
        [
          for (final c in (explorar as RutasPorCercania).cercanas)
            c.distanciaKm,
        ],
        [1.4, 6.2],
      );
    });

    test('pregunta desde donde está y con el radio de cercanía', () async {
      await leer(EstadoPermiso.concedido);

      expect(repositorio.ultimaConsultaCercana, (
        latitud: 6.2442,
        longitud: -75.5812,
        radioKm: radioRutasCercanasKm,
      ));
      expect(radioRutasCercanasKm, 50);
      // No hace falta la lista por fecha: ya está la de cercanía.
      expect(repositorio.consultasPublicadas, 0);
    });

    test('recuerda desde dónde se ordenó', () async {
      final explorar = await leer(EstadoPermiso.concedido);

      final desde = (explorar as RutasPorCercania).desde;
      expect(desde.latitud, 6.2442);
      expect(desde.longitud, -75.5812);
    });
  });

  group('sin saber dónde está, las más recientes', () {
    test('sin permiso de ubicación', () async {
      final explorar = await leer(EstadoPermiso.denegado);

      expect(explorar, isA<RutasRecientes>());
      expect((explorar as RutasRecientes).motivo, isA<UbicacionSinPermiso>());
      expect([for (final r in explorar.rutas) r.id], ['r-1', 'r-2']);
      expect(repositorio.consultasCercanas, 0);
    });

    test('con la ubicación del teléfono apagada', () async {
      fuente.servicio = false;

      final explorar = await leer(EstadoPermiso.concedido);

      expect(explorar, isA<RutasRecientes>());
      expect((explorar as RutasRecientes).motivo, isA<UbicacionApagada>());
      expect(repositorio.consultasCercanas, 0);
    });

    test('si el GPS no responde', () async {
      fuente.errorAlLeer = Exception('sin fix');

      final explorar = await leer(EstadoPermiso.concedido);

      expect(explorar, isA<RutasRecientes>());
      expect((explorar as RutasRecientes).motivo, isA<UbicacionNoSePudo>());
    });
  });

  test('si la base falla, el error llega a la pantalla', () async {
    repositorio.error = Exception('sin red');

    await expectLater(leer(EstadoPermiso.concedido), throwsA(isA<Exception>()));
  });
}
