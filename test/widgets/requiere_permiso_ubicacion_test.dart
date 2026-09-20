import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:traza/models/estado_permisos.dart';
import 'package:traza/services/permisos_service.dart';
import 'package:traza/services/permisos_usuario_service.dart';
import 'package:traza/widgets/requiere_permiso_ubicacion.dart';

class _MockPermisosService extends Mock implements PermisosService {}

class _RepositorioFalso implements PermisosUsuarioRepository {
  @override
  Future<void> guardar(TipoPermiso tipo, {required bool concedido}) async {}
}

/// Pruebas del aviso cuando falta el permiso de ubicación (SCRUM-82).
void main() {
  late _MockPermisosService servicio;

  setUp(() {
    servicio = _MockPermisosService();
    when(
      () => servicio.estadoSalud(),
    ).thenAnswer((_) async => EstadoPermiso.desconocido);
    when(() => servicio.abrirAjustes()).thenAnswer((_) async {});
  });

  void cuandoUbicacionEsta(EstadoPermiso estado) {
    when(() => servicio.estadoUbicacion()).thenAnswer((_) async => estado);
  }

  Future<void> abrirEntrenamiento(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/inicio',
      routes: [
        GoRoute(
          path: '/inicio',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () => context.push('/tracking'),
              child: const Text('Pantalla Inicio'),
            ),
          ),
        ),
        GoRoute(
          path: '/tracking',
          builder: (context, state) => const RequierePermisoUbicacion(
            child: Scaffold(body: Text('Entrenamiento en curso')),
          ),
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
    await tester.tap(find.text('Pantalla Inicio'));
    await tester.pumpAndSettle();
  }

  testWidgets('con permiso entra directo al entrenamiento', (tester) async {
    cuandoUbicacionEsta(EstadoPermiso.concedido);

    await abrirEntrenamiento(tester);

    expect(find.text('Entrenamiento en curso'), findsOneWidget);
    expect(find.text(RequierePermisoUbicacion.mensaje), findsNothing);
  });

  testWidgets('sin permiso explica por qué y no abre el entrenamiento', (
    tester,
  ) async {
    cuandoUbicacionEsta(EstadoPermiso.denegado);

    await abrirEntrenamiento(tester);

    expect(find.text(RequierePermisoUbicacion.mensaje), findsOneWidget);
    expect(find.text('Aceptar'), findsOneWidget);
    expect(find.text('Entrenamiento en curso'), findsNothing);
  });

  testWidgets('"Aceptar" pide el permiso y, si lo da, sigue', (tester) async {
    cuandoUbicacionEsta(EstadoPermiso.denegado);
    when(
      () => servicio.solicitarUbicacion(),
    ).thenAnswer((_) async => EstadoPermiso.concedido);
    await abrirEntrenamiento(tester);

    await tester.tap(find.text('Aceptar'));
    await tester.pumpAndSettle();

    verify(() => servicio.solicitarUbicacion()).called(1);
    expect(find.text('Entrenamiento en curso'), findsOneWidget);
  });

  testWidgets('si lo vuelve a negar, el aviso sigue ahí', (tester) async {
    cuandoUbicacionEsta(EstadoPermiso.denegado);
    when(
      () => servicio.solicitarUbicacion(),
    ).thenAnswer((_) async => EstadoPermiso.denegado);
    await abrirEntrenamiento(tester);

    await tester.tap(find.text('Aceptar'));
    await tester.pumpAndSettle();

    expect(find.text(RequierePermisoUbicacion.mensaje), findsOneWidget);
  });

  testWidgets('bloqueado: "Aceptar" abre los ajustes', (tester) async {
    cuandoUbicacionEsta(EstadoPermiso.bloqueado);
    await abrirEntrenamiento(tester);

    expect(find.textContaining('ajustes del teléfono'), findsOneWidget);
    await tester.tap(find.text('Aceptar'));
    await tester.pumpAndSettle();

    verify(() => servicio.abrirAjustes()).called(1);
    verifyNever(() => servicio.solicitarUbicacion());
  });

  testWidgets('"Volver" regresa a donde estaba', (tester) async {
    cuandoUbicacionEsta(EstadoPermiso.denegado);
    await abrirEntrenamiento(tester);

    await tester.tap(find.text('Volver'));
    await tester.pumpAndSettle();

    expect(find.text('Pantalla Inicio'), findsOneWidget);
  });
}
