import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:traza/models/estado_permisos.dart';
import 'package:traza/screens/onboarding/permisos_screen.dart';
import 'package:traza/services/permisos_service.dart';
import 'package:traza/services/permisos_usuario_service.dart';

class _MockPermisosService extends Mock implements PermisosService {}

/// La pantalla no prueba el guardado (eso está en permisos_provider_test):
/// solo evita que intente hablar con Supabase.
class _RepositorioFalso implements PermisosUsuarioRepository {
  @override
  Future<void> guardar(TipoPermiso tipo, {required bool concedido}) async {}
}

/// Pruebas de la pantalla de permisos (SCRUM-76) y del permiso de ubicación
/// (SCRUM-77).
void main() {
  late _MockPermisosService servicio;

  setUp(() {
    servicio = _MockPermisosService();
    when(
      () => servicio.estadoUbicacion(),
    ).thenAnswer((_) async => EstadoPermiso.denegado);
    when(
      () => servicio.estadoSalud(),
    ).thenAnswer((_) async => EstadoPermiso.denegado);
    when(() => servicio.abrirAjustes()).thenAnswer((_) async {});
    when(() => servicio.instalarProveedorSalud()).thenAnswer((_) async {});
  });

  Future<void> montar(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/permisos',
      routes: [
        GoRoute(
          path: '/permisos',
          builder: (context, state) => const PermisosScreen(),
        ),
        GoRoute(
          path: '/inicio',
          builder: (context, state) =>
              const Scaffold(body: Text('Pantalla Inicio')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          permisosServiceProvider.overrideWithValue(servicio),
          permisosUsuarioRepositoryProvider.overrideWithValue(
            _RepositorioFalso(),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
  }

  /// Deja que el aviso termine su temporizador.
  Future<void> esperarAviso(WidgetTester tester) =>
      tester.pumpAndSettle(const Duration(seconds: 3));

  testWidgets('explica para qué se usa cada permiso', (tester) async {
    await montar(tester);

    expect(find.text('Ubicación'), findsOneWidget);
    expect(find.textContaining('trazar tu recorrido'), findsOneWidget);
    expect(find.text('Permitir ubicación'), findsOneWidget);

    expect(find.text('Datos de salud'), findsOneWidget);
    expect(find.textContaining('métricas de salud'), findsOneWidget);
    expect(find.text('Permitir acceso'), findsOneWidget);
  });

  testWidgets('"Ahora no" avisa que se puede activar después', (tester) async {
    await montar(tester);

    await tester.tap(find.text('Ahora no').first);
    await tester.pump();

    expect(
      find.text('Podrás activarlo luego cuando lo necesites'),
      findsOneWidget,
    );
    await esperarAviso(tester);
  });

  testWidgets('"Continuar" lleva a Inicio', (tester) async {
    await montar(tester);

    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(find.text('Pantalla Inicio'), findsOneWidget);
  });

  group('Permiso de ubicación', () {
    testWidgets('si ya estaba concedido, la tarjeta lo muestra', (
      tester,
    ) async {
      when(
        () => servicio.estadoUbicacion(),
      ).thenAnswer((_) async => EstadoPermiso.concedido);
      await montar(tester);

      expect(find.text('Permiso concedido'), findsOneWidget);
      expect(find.text('Permitir ubicación'), findsNothing);
    });

    testWidgets('al aceptarlo la tarjeta pasa a concedido', (tester) async {
      when(
        () => servicio.solicitarUbicacion(),
      ).thenAnswer((_) async => EstadoPermiso.concedido);
      await montar(tester);

      await tester.tap(find.text('Permitir ubicación'));
      await tester.pumpAndSettle();

      verify(() => servicio.solicitarUbicacion()).called(1);
      expect(find.text('Permiso concedido'), findsOneWidget);
    });

    testWidgets('al negarlo explica qué no podrá hacer', (tester) async {
      when(
        () => servicio.solicitarUbicacion(),
      ).thenAnswer((_) async => EstadoPermiso.denegado);
      await montar(tester);

      await tester.tap(find.text('Permitir ubicación'));
      await tester.pump();

      expect(
        find.text('Sin ubicación no podrás registrar tus recorridos'),
        findsOneWidget,
      );
      expect(find.text('Permitir ubicación'), findsOneWidget);
      await esperarAviso(tester);
    });

    testWidgets('si está bloqueado, ofrece abrir los ajustes', (tester) async {
      when(
        () => servicio.solicitarUbicacion(),
      ).thenAnswer((_) async => EstadoPermiso.bloqueado);
      await montar(tester);

      await tester.tap(find.text('Permitir ubicación'));
      await tester.pumpAndSettle();
      expect(find.text('Ubicación desactivada'), findsOneWidget);

      await tester.tap(find.text('Abrir ajustes'));
      await tester.pumpAndSettle();

      verify(() => servicio.abrirAjustes()).called(1);
    });
  });

  group('Datos de salud', () {
    testWidgets('al aceptarlo la tarjeta pasa a concedido', (tester) async {
      when(
        () => servicio.solicitarSalud(),
      ).thenAnswer((_) async => EstadoPermiso.concedido);
      await montar(tester);

      await tester.tap(find.text('Permitir acceso'));
      await tester.pumpAndSettle();

      verify(() => servicio.solicitarSalud()).called(1);
      expect(find.text('Permiso concedido'), findsOneWidget);
    });

    testWidgets('al negarlo avisa que el resumen irá sin esas métricas', (
      tester,
    ) async {
      when(
        () => servicio.solicitarSalud(),
      ).thenAnswer((_) async => EstadoPermiso.denegado);
      await montar(tester);

      await tester.tap(find.text('Permitir acceso'));
      await tester.pump();

      expect(
        find.text('Tu resumen no mostrará métricas de salud'),
        findsOneWidget,
      );
      await esperarAviso(tester);
    });

    testWidgets('en Android sin Health Connect ofrece instalarlo', (
      tester,
    ) async {
      when(
        () => servicio.solicitarSalud(),
      ).thenAnswer((_) async => EstadoPermiso.noDisponible);
      await montar(tester);

      await tester.tap(find.text('Permitir acceso'));
      await tester.pumpAndSettle();
      expect(find.text('Falta Health Connect'), findsOneWidget);

      await tester.tap(find.text('Instalar'));
      await tester.pumpAndSettle();

      verify(() => servicio.instalarProveedorSalud()).called(1);
    });
  });
}
