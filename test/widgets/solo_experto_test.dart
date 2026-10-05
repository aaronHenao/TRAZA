import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/rol_ganado.dart';
import 'package:traza/services/roles_service.dart';
import 'package:traza/widgets/solo_experto.dart';

class _RolesFalso implements RolesRepository {
  _RolesFalso(this.respuesta);

  final Future<List<RolGanado>> Function() respuesta;
  var consultas = 0;

  @override
  Future<List<RolGanado>> misRoles() {
    consultas++;
    return respuesta();
  }
}

/// Pruebas de la barrera de lo exclusivo del Runner Experto (SCRUM-228).
///
/// Es la mitad de presentación del control de acceso. La otra mitad, que la
/// base rechace la acción aunque la interfaz se salte, vive en las policies
/// que usan `es_experto()`.
void main() {
  final experto = RolGanado(
    rol: RolGanable.experto,
    otorgadoEn: DateTime.utc(2026, 10, 2, 15),
  );

  late _RolesFalso repositorio;

  Future<void> abrir(
    WidgetTester tester, {
    required Future<List<RolGanado>> Function() roles,
    bool esperar = true,
  }) async {
    repositorio = _RolesFalso(roles);
    final router = GoRouter(
      initialLocation: '/exclusivo',
      routes: [
        GoRoute(
          path: '/exclusivo',
          builder: (_, _) =>
              const SoloExperto(hijo: Scaffold(body: Text('Validar rutas'))),
        ),
        GoRoute(
          path: '/inicio',
          builder: (_, _) => const Scaffold(body: Text('Portada del corredor')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [rolesRepositoryProvider.overrideWithValue(repositorio)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    if (esperar) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  testWidgets('quien tiene el rol entra', (tester) async {
    await abrir(tester, roles: () async => [experto]);

    expect(find.text('Validar rutas'), findsOneWidget);
  });

  testWidgets('quien no lo ha desbloqueado no entra, y se le dice por qué', (
    tester,
  ) async {
    await abrir(tester, roles: () async => const []);

    expect(find.text('Validar rutas'), findsNothing);
    expect(find.text('Esto es de Runner Experto'), findsOneWidget);
    // No es un regaño: se le dice cómo se consigue.
    expect(
      find.text('Sigue sumando niveles y se desbloquea solo.'),
      findsOneWidget,
    );
  });

  testWidgets('desde el aviso se vuelve al inicio', (tester) async {
    await abrir(tester, roles: () async => const []);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Volver al inicio'));
    await tester.pumpAndSettle();

    expect(find.text('Portada del corredor'), findsOneWidget);
  });

  testWidgets('si los roles no se pueden leer, no entra', (tester) async {
    // Al revés se abriría una pantalla cuya acción la base va a rechazar.
    await abrir(tester, roles: () async => throw Exception('sin red'));

    expect(find.text('Validar rutas'), findsNothing);
    expect(find.text('Esto es de Runner Experto'), findsOneWidget);
  });

  testWidgets('mientras resuelve el rol no enseña la pantalla', (tester) async {
    final pendiente = Completer<List<RolGanado>>();
    await abrir(tester, roles: () => pendiente.future, esperar: false);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Validar rutas'), findsNothing);

    pendiente.complete([experto]);
    await tester.pumpAndSettle();
    expect(find.text('Validar rutas'), findsOneWidget);
  });

  testWidgets('el rol se consulta, no se supone', (tester) async {
    await abrir(tester, roles: () async => [experto]);

    expect(repositorio.consultas, 1);
  });
}
