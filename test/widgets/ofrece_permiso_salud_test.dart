import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:traza/models/estado_permisos.dart';
import 'package:traza/services/permisos_service.dart';
import 'package:traza/services/permisos_usuario_service.dart';
import 'package:traza/widgets/ofrece_permiso_salud.dart';

class _MockPermisosService extends Mock implements PermisosService {}

class _RepositorioFalso implements PermisosUsuarioRepository {
  @override
  Future<void> guardar(TipoPermiso tipo, {required bool concedido}) async {}
}

/// Pruebas del acceso sin datos de salud (SCRUM-83).
void main() {
  late _MockPermisosService servicio;

  setUp(() {
    servicio = _MockPermisosService();
    when(
      () => servicio.estadoUbicacion(),
    ).thenAnswer((_) async => EstadoPermiso.concedido);
  });

  void cuandoSaludEsta(EstadoPermiso estado) {
    when(() => servicio.estadoSalud()).thenAnswer((_) async => estado);
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
          builder: (context, state) => OfrecePermisoSalud(
            child: Scaffold(
              appBar: AppBar(),
              body: const Text('Entrenamiento en curso'),
            ),
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

  testWidgets('con permiso entra directo', (tester) async {
    cuandoSaludEsta(EstadoPermiso.concedido);

    await abrirEntrenamiento(tester);

    expect(find.text('Entrenamiento en curso'), findsOneWidget);
  });

  testWidgets('sin Health Connect no pregunta: no hay de dónde leer', (
    tester,
  ) async {
    cuandoSaludEsta(EstadoPermiso.noDisponible);

    await abrirEntrenamiento(tester);

    expect(find.text('Entrenamiento en curso'), findsOneWidget);
  });

  testWidgets('sin permiso ofrece concederlo antes de entrenar', (
    tester,
  ) async {
    cuandoSaludEsta(EstadoPermiso.denegado);

    await abrirEntrenamiento(tester);

    expect(find.text('¿Registrar tus datos de salud?'), findsOneWidget);
    expect(find.text('Entrenamiento en curso'), findsNothing);
  });

  testWidgets('si lo concede, entra al entrenamiento', (tester) async {
    cuandoSaludEsta(EstadoPermiso.denegado);
    when(
      () => servicio.solicitarSalud(),
    ).thenAnswer((_) async => EstadoPermiso.concedido);
    await abrirEntrenamiento(tester);

    await tester.tap(find.text('Permitir'));
    await tester.pumpAndSettle();

    verify(() => servicio.solicitarSalud()).called(1);
    expect(find.text('Entrenamiento en curso'), findsOneWidget);
  });

  testWidgets('si lo niega, entra igual sin datos de salud', (tester) async {
    cuandoSaludEsta(EstadoPermiso.denegado);
    when(
      () => servicio.solicitarSalud(),
    ).thenAnswer((_) async => EstadoPermiso.denegado);
    await abrirEntrenamiento(tester);

    await tester.tap(find.text('Permitir'));
    await tester.pumpAndSettle();

    expect(find.text('Entrenamiento en curso'), findsOneWidget);
  });

  testWidgets('"Continuar sin datos de salud" entra sin pedir nada', (
    tester,
  ) async {
    cuandoSaludEsta(EstadoPermiso.denegado);
    await abrirEntrenamiento(tester);

    await tester.tap(find.text('Continuar sin datos de salud'));
    await tester.pumpAndSettle();

    verifyNever(() => servicio.solicitarSalud());
    expect(find.text('Entrenamiento en curso'), findsOneWidget);
  });

  testWidgets('no vuelve a preguntar en el siguiente entrenamiento', (
    tester,
  ) async {
    cuandoSaludEsta(EstadoPermiso.denegado);
    await abrirEntrenamiento(tester);
    await tester.tap(find.text('Continuar sin datos de salud'));
    await tester.pumpAndSettle();

    // Sale del entrenamiento y vuelve a entrar.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pantalla Inicio'));
    await tester.pumpAndSettle();

    expect(find.text('¿Registrar tus datos de salud?'), findsNothing);
    expect(find.text('Entrenamiento en curso'), findsOneWidget);
  });
}
