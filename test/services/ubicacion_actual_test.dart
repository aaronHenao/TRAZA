import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:traza/models/estado_permisos.dart';
import 'package:traza/services/permisos_provider.dart';
import 'package:traza/services/permisos_service.dart';
import 'package:traza/services/permisos_usuario_service.dart';
import 'package:traza/services/ubicacion_provider.dart';

import '../utiles/fuente_ubicacion_falsa.dart';

class _MockPermisosService extends Mock implements PermisosService {}

/// Lo que la app guarda en `permisos_usuario`: aquí no interesa.
class _PermisosGuardadosFalso implements PermisosUsuarioRepository {
  @override
  Future<void> guardar(TipoPermiso tipo, {required bool concedido}) async {}
}

/// Pruebas del servicio de ubicación del usuario (SCRUM-245).
///
/// Lo que se comprueba es que una sola lectura baste, que se apoye en los
/// permisos que ya existen en vez de pedirlos por su cuenta, y que cada
/// motivo de "no se sabe dónde está" llegue distinto a quien lo use.
void main() {
  late _MockPermisosService permisos;
  late FuenteUbicacionFalsa fuente;

  setUp(() {
    permisos = _MockPermisosService();
    fuente = FuenteUbicacionFalsa();
    when(
      () => permisos.estadoSalud(),
    ).thenAnswer((_) async => EstadoPermiso.desconocido);
    when(() => permisos.abrirAjustes()).thenAnswer((_) async {});
  });

  tearDown(() => fuente.cerrar());

  /// Un contenedor con la ubicación falsa y el permiso que diga la prueba.
  ProviderContainer contenedor(EstadoPermiso ubicacion) {
    when(() => permisos.estadoUbicacion()).thenAnswer((_) async => ubicacion);

    final container = ProviderContainer(
      overrides: [
        permisosServiceProvider.overrideWithValue(permisos),
        permisosUsuarioRepositoryProvider.overrideWithValue(
          _PermisosGuardadosFalso(),
        ),
        fuenteUbicacionProvider.overrideWithValue(fuente),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Espera a que la consulta de permisos del arranque termine, que es lo
  /// que hace la app antes de pintar nada.
  Future<UbicacionUsuario> leer(ProviderContainer container) async {
    await container.read(permisosProvider.notifier).actualizar();
    return container.read(ubicacionActualProvider.future);
  }

  group('con el permiso concedido', () {
    test('devuelve la posición del dispositivo', () async {
      fuente.puntoActual = puntoDePrueba(latitud: 6.2442, longitud: -75.5812);
      final container = contenedor(EstadoPermiso.concedido);

      final ubicacion = await leer(container);

      expect(ubicacion, isA<UbicacionConocida>());
      final punto = (ubicacion as UbicacionConocida).punto;
      expect(punto.latitud, 6.2442);
      expect(punto.longitud, -75.5812);
    });

    test('una sola lectura, no el stream del rastreo', () async {
      final container = contenedor(EstadoPermiso.concedido);

      await leer(container);

      expect(fuente.lecturasPuntuales, 1);
      // Abrir el stream dejaría el GPS encendido gastando batería.
      expect(fuente.suscripcionesAbiertas, 0);
    });

    test('se rinde a los diez segundos', () async {
      final container = contenedor(EstadoPermiso.concedido);

      await leer(container);

      expect(fuente.ultimoTiempoMaximo, tiempoMaximoUbicacion);
      expect(tiempoMaximoUbicacion, const Duration(seconds: 10));
    });
  });

  group('cuando no se sabe dónde está', () {
    test('sin permiso no se le pregunta nada al GPS', () async {
      final container = contenedor(EstadoPermiso.denegado);

      final ubicacion = await leer(container);

      expect(ubicacion, isA<UbicacionSinPermiso>());
      expect(fuente.lecturasPuntuales, 0);
    });

    test('con el permiso bloqueado tampoco', () async {
      final container = contenedor(EstadoPermiso.bloqueado);

      final ubicacion = await leer(container);

      expect(ubicacion, isA<UbicacionSinPermiso>());
      expect(fuente.lecturasPuntuales, 0);
    });

    test('con la ubicación del teléfono apagada lo dice aparte', () async {
      // El permiso se tiene; lo que falta es el GPS encendido, y eso se
      // arregla en los ajustes del sistema, no concediendo nada.
      fuente.servicio = false;
      final container = contenedor(EstadoPermiso.concedido);

      final ubicacion = await leer(container);

      expect(ubicacion, isA<UbicacionApagada>());
      expect(fuente.lecturasPuntuales, 0);
    });

    test('si el GPS no responde, lo dice en vez de reventar', () async {
      fuente.errorAlLeer = Exception('sin fix');
      final container = contenedor(EstadoPermiso.concedido);

      final ubicacion = await leer(container);

      expect(ubicacion, isA<UbicacionNoSePudo>());
    });
  });

  test(
    'al conceder el permiso se vuelve a leer sin que nadie lo pida',
    () async {
      final container = contenedor(EstadoPermiso.denegado);
      expect(await leer(container), isA<UbicacionSinPermiso>());

      // El usuario lo concede desde la pantalla: el estado de permisos
      // cambia y la ubicación se recalcula sola.
      when(
        () => permisos.solicitarUbicacion(),
      ).thenAnswer((_) async => EstadoPermiso.concedido);
      await container.read(permisosProvider.notifier).solicitarUbicacion();

      final ubicacion = await container.read(ubicacionActualProvider.future);
      expect(ubicacion, isA<UbicacionConocida>());
      expect(fuente.lecturasPuntuales, 1);
    },
  );
}
