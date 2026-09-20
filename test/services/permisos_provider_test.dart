import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:traza/models/estado_permisos.dart';
import 'package:traza/services/permisos_provider.dart';
import 'package:traza/services/permisos_service.dart';
import 'package:traza/services/permisos_usuario_service.dart';

class _MockPermisosService extends Mock implements PermisosService {}

class _MockPermisosUsuarioRepository extends Mock
    implements PermisosUsuarioRepository {}

void main() {
  late _MockPermisosService servicio;
  late _MockPermisosUsuarioRepository repositorio;
  late ProviderContainer container;

  setUpAll(() => registerFallbackValue(TipoPermiso.ubicacion));

  setUp(() {
    servicio = _MockPermisosService();
    repositorio = _MockPermisosUsuarioRepository();
    when(
      () => repositorio.guardar(any(), concedido: any(named: 'concedido')),
    ).thenAnswer((_) async {});
    when(
      () => servicio.estadoUbicacion(),
    ).thenAnswer((_) async => EstadoPermiso.denegado);
    when(
      () => servicio.estadoSalud(),
    ).thenAnswer((_) async => EstadoPermiso.desconocido);
    container = ProviderContainer(
      overrides: [
        permisosServiceProvider.overrideWithValue(servicio),
        permisosUsuarioRepositoryProvider.overrideWithValue(repositorio),
      ],
    );
    addTearDown(container.dispose);
  });

  test('al crearse consulta el permiso sin mostrar la ventana', () async {
    container.read(permisosProvider);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(permisosProvider).ubicacion, EstadoPermiso.denegado);
    verifyNever(() => servicio.solicitarUbicacion());
  });

  test('si el usuario acepta, queda concedido', () async {
    when(
      () => servicio.solicitarUbicacion(),
    ).thenAnswer((_) async => EstadoPermiso.concedido);

    final resultado = await container
        .read(permisosProvider.notifier)
        .solicitarUbicacion();

    expect(resultado, EstadoPermiso.concedido);
    expect(container.read(permisosProvider).ubicacion, EstadoPermiso.concedido);
    expect(container.read(permisosProvider).solicitandoUbicacion, isFalse);
  });

  test('si el sistema lo tiene bloqueado, lo informa', () async {
    when(
      () => servicio.solicitarUbicacion(),
    ).thenAnswer((_) async => EstadoPermiso.bloqueado);

    final resultado = await container
        .read(permisosProvider.notifier)
        .solicitarUbicacion();

    expect(resultado, EstadoPermiso.bloqueado);
  });

  test('un error del plugin se trata como denegado', () async {
    when(() => servicio.solicitarUbicacion()).thenThrow(Exception('plugin'));

    final resultado = await container
        .read(permisosProvider.notifier)
        .solicitarUbicacion();

    expect(resultado, EstadoPermiso.denegado);
    expect(container.read(permisosProvider).solicitandoUbicacion, isFalse);
  });

  test('actualizar refleja el cambio hecho en los ajustes', () async {
    container.read(permisosProvider);
    await Future<void>.delayed(Duration.zero);
    when(
      () => servicio.estadoUbicacion(),
    ).thenAnswer((_) async => EstadoPermiso.concedido);

    await container.read(permisosProvider.notifier).actualizar();

    expect(container.read(permisosProvider).ubicacion, EstadoPermiso.concedido);
  });

  group('Datos de salud', () {
    test('al crearse consulta también el de salud', () async {
      when(
        () => servicio.estadoSalud(),
      ).thenAnswer((_) async => EstadoPermiso.concedido);

      container.read(permisosProvider);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(permisosProvider).salud, EstadoPermiso.concedido);
      verifyNever(() => servicio.solicitarSalud());
    });

    test('si el usuario acepta, queda concedido', () async {
      when(
        () => servicio.solicitarSalud(),
      ).thenAnswer((_) async => EstadoPermiso.concedido);

      final resultado = await container
          .read(permisosProvider.notifier)
          .solicitarSalud();

      expect(resultado, EstadoPermiso.concedido);
      expect(container.read(permisosProvider).salud, EstadoPermiso.concedido);
      expect(container.read(permisosProvider).solicitandoSalud, isFalse);
    });

    test('sin Health Connect informa que no está disponible', () async {
      when(
        () => servicio.solicitarSalud(),
      ).thenAnswer((_) async => EstadoPermiso.noDisponible);

      final resultado = await container
          .read(permisosProvider.notifier)
          .solicitarSalud();

      expect(resultado, EstadoPermiso.noDisponible);
    });

    test('un error al consultar no tumba el de ubicación', () async {
      when(() => servicio.estadoSalud()).thenThrow(Exception('plugin'));

      container.read(permisosProvider);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final estado = container.read(permisosProvider);
      expect(estado.ubicacion, EstadoPermiso.denegado);
      expect(estado.salud, EstadoPermiso.desconocido);
    });
  });

  group('Guardado en Supabase', () {
    test('al pedir la ubicación guarda la respuesta', () async {
      when(
        () => servicio.solicitarUbicacion(),
      ).thenAnswer((_) async => EstadoPermiso.concedido);

      await container.read(permisosProvider.notifier).solicitarUbicacion();

      verify(
        () => repositorio.guardar(TipoPermiso.ubicacion, concedido: true),
      ).called(1);
    });

    test('bloqueado se guarda como no concedido', () async {
      when(
        () => servicio.solicitarUbicacion(),
      ).thenAnswer((_) async => EstadoPermiso.bloqueado);

      await container.read(permisosProvider.notifier).solicitarUbicacion();

      verify(
        () => repositorio.guardar(TipoPermiso.ubicacion, concedido: false),
      ).called(1);
    });

    test('al pedir salud guarda la respuesta', () async {
      when(
        () => servicio.solicitarSalud(),
      ).thenAnswer((_) async => EstadoPermiso.denegado);

      await container.read(permisosProvider.notifier).solicitarSalud();

      verify(
        () => repositorio.guardar(TipoPermiso.salud, concedido: false),
      ).called(1);
    });

    test('sin Health Connect no hay decisión que guardar', () async {
      when(
        () => servicio.solicitarSalud(),
      ).thenAnswer((_) async => EstadoPermiso.noDisponible);

      await container.read(permisosProvider.notifier).solicitarSalud();

      verifyNever(
        () => repositorio.guardar(
          TipoPermiso.salud,
          concedido: any(named: 'concedido'),
        ),
      );
    });

    test('al actualizar solo guarda lo que cambió', () async {
      container.read(permisosProvider);
      await Future<void>.delayed(Duration.zero);
      // Primera consulta: ubicación pasa de desconocido a denegado.
      verify(
        () => repositorio.guardar(TipoPermiso.ubicacion, concedido: false),
      ).called(1);

      await container.read(permisosProvider.notifier).actualizar();
      verifyNever(
        () => repositorio.guardar(any(), concedido: any(named: 'concedido')),
      );

      when(
        () => servicio.estadoUbicacion(),
      ).thenAnswer((_) async => EstadoPermiso.concedido);
      await container.read(permisosProvider.notifier).actualizar();
      verify(
        () => repositorio.guardar(TipoPermiso.ubicacion, concedido: true),
      ).called(1);
    });

    test('si Supabase falla, el permiso queda igual en la app', () async {
      when(
        () => repositorio.guardar(any(), concedido: any(named: 'concedido')),
      ).thenAnswer((_) async => throw Exception('sin red'));
      when(
        () => servicio.solicitarUbicacion(),
      ).thenAnswer((_) async => EstadoPermiso.concedido);

      final resultado = await container
          .read(permisosProvider.notifier)
          .solicitarUbicacion();
      await Future<void>.delayed(Duration.zero);

      expect(resultado, EstadoPermiso.concedido);
      expect(
        container.read(permisosProvider).ubicacion,
        EstadoPermiso.concedido,
      );
    });
  });
}
